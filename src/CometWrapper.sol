// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {CometInterface, TotalsBasic} from "./vendor/CometInterface.sol";
import {CometMath} from "./vendor/CometMath.sol";
import {ICometRewards} from "./vendor/ICometRewards.sol";
import "forge-std/console.sol";

contract CometWrapper is ERC4626, CometMath {
    using SafeTransferLib for ERC20;

    uint64 internal constant FACTOR_SCALE = 1e18;
    uint64 internal constant BASE_INDEX_SCALE = 1e15;
    uint256 constant TRACKING_INDEX_SCALE = 1e15;
    uint64 constant RESCALE_FACTOR = 1e12;

    struct UserBasic {
        uint104 principal;
        uint64 baseTrackingAccrued;
        uint64 baseTrackingIndex;
    }

    event RewardClaimed(address indexed src, address indexed recipient, address indexed token, uint256 amount);

    mapping(address => UserBasic) public userBasic;
    mapping(address => uint256) public rewardsClaimed;

    uint40 internal lastAccrualTime;
    uint256 public underlyingPrincipal;
    CometInterface immutable comet;
    ERC20 public immutable rewardERC20;
    ICometRewards public immutable cometRewards;

    constructor(
        ERC20 _asset,
        ERC20 _rewardERC20,
        ICometRewards _cometRewards,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset, _name, _symbol) {
        comet = CometInterface(address(_asset));
        lastAccrualTime = getNowInternal();
        rewardERC20 = _rewardERC20;
        cometRewards = _cometRewards;
    }

    function totalAssets() public view override returns (uint256) {
        uint64 baseSupplyIndex_ = accruedSupplyIndex(getNowInternal() - lastAccrualTime);
        uint256 principal = underlyingPrincipal;
        return principal > 0 ? presentValueSupply(baseSupplyIndex_, principal) : 0;
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        accrueInternal();
        updatePrincipals(receiver, signed256(assets));
        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        accrueInternal();
        updatePrincipals(receiver, signed256(assets));
        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        accrueInternal();
        updatePrincipals(owner, -signed256(assets));

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        accrueInternal();
        updatePrincipals(owner, -signed256(assets));

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        transferInternal(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 allowed = msg.sender == from ? type(uint256).max : allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        transferInternal(from, to, amount);
        return true;
    }

    function transferInternal(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;

        updateTransferPrincipals(from, to, amount);

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    function underlyingBalance(address account) public view returns (uint256) {
        uint64 baseSupplyIndex_ = accruedSupplyIndex(getNowInternal() - lastAccrualTime);
        uint256 principal = userBasic[account].principal;
        return principal > 0 ? presentValueSupply(baseSupplyIndex_, principal) : 0;
    }

    function updatePrincipals(address account, int256 balanceChange) internal {
        UserBasic memory basic = userBasic[account];
        uint104 principal = basic.principal;
        (uint64 baseSupplyIndex,) = getSupplyIndices();

        if (balanceChange != 0) {
            basic.principal = updatedPrincipal(principal, baseSupplyIndex, balanceChange);
            userBasic[account] = basic;
            // Need to use the same method of updating wrapper's principal so that `totalAssets()`
            // will match with `comet.balanceOf(wrapper)`
            underlyingPrincipal = updatedPrincipal(underlyingPrincipal, baseSupplyIndex, balanceChange);
        }
    }

    function updateTransferPrincipals(address from, address to, uint256 shares) internal {
        uint256 _totalAssets = totalAssets();
        uint256 assets = convertToAssets(shares);
        uint104 principalChange = safe104(assets * underlyingPrincipal / _totalAssets);
        userBasic[from].principal -= principalChange;
        userBasic[to].principal += principalChange;
    }

    function updatedPrincipal(uint256 principal, uint64 baseSupplyIndex, int256 balanceChange)
        internal
        pure
        returns (uint104)
    {
        int256 balance = signed256(presentValueSupply(baseSupplyIndex, principal)) + balanceChange;
        return principalValueSupply(baseSupplyIndex, unsigned256(balance));
    }

    function accrueInternal() internal {
        uint40 now_ = getNowInternal();
        uint256 timeElapsed = uint256(now_ - lastAccrualTime);
        if (timeElapsed > 0) {
            comet.accrueAccount(address(this));
            lastAccrualTime = now_;
        }
    }

    function getRewardOwed(address account) external returns (uint256) {
        UserBasic memory basic = accrueRewards(account);
        uint256 claimed = rewardsClaimed[account];
        uint256 accrued = basic.baseTrackingAccrued * RESCALE_FACTOR;
        uint256 owed = accrued > claimed ? accrued - claimed : 0;

        return owed;
    }

    function claimTo(address to) external {
        address from = msg.sender;
        UserBasic memory basic = accrueRewards(from);

        uint256 claimed = rewardsClaimed[from];
        uint256 accrued = basic.baseTrackingAccrued * RESCALE_FACTOR;

        if (accrued > claimed) {
            uint256 owed = accrued - claimed;
            rewardsClaimed[from] = accrued;

            emit RewardClaimed(from, to, address(rewardERC20), owed);
            cometRewards.claimTo(address(comet), address(this), address(this), true);
            rewardERC20.safeTransfer(to, owed);
        }
    }

    function accrueRewards(address account) public returns (UserBasic memory) {
        UserBasic memory basic = userBasic[account];
        comet.accrueAccount(address(this));

        (, uint64 trackingSupplyIndex) = getSupplyIndices();
        uint256 indexDelta = uint256(trackingSupplyIndex - basic.baseTrackingIndex);
        basic.baseTrackingAccrued += safe64((uint104(basic.principal) * indexDelta) / TRACKING_INDEX_SCALE);
        basic.baseTrackingIndex = trackingSupplyIndex;
        userBasic[account] = basic;

        return basic;
    }

    function accruedSupplyIndex(uint256 timeElapsed) internal view returns (uint64) {
        (uint64 baseSupplyIndex_,) = getSupplyIndices();
        if (timeElapsed > 0) {
            uint256 utilization = comet.getUtilization();
            uint256 supplyRate = comet.getSupplyRate(utilization);
            baseSupplyIndex_ += safe64(mulFactor(baseSupplyIndex_, supplyRate * timeElapsed));
        }
        return baseSupplyIndex_;
    }

    function getSupplyIndices() internal view returns (uint64 baseSupplyIndex_, uint64 trackingSupplyIndex_) {
        TotalsBasic memory totals = comet.totalsBasic();
        baseSupplyIndex_ = totals.baseSupplyIndex;
        trackingSupplyIndex_ = totals.trackingSupplyIndex;
    }

    function mulFactor(uint256 n, uint256 factor) internal pure returns (uint256) {
        return n * factor / FACTOR_SCALE;
    }

    error TimestampTooLarge();

    function presentValueSupply(uint64 baseSupplyIndex_, uint256 principalValue_) internal pure returns (uint256) {
        return principalValue_ * baseSupplyIndex_ / BASE_INDEX_SCALE;
    }

    function principalValueSupply(uint64 baseSupplyIndex_, uint256 presentValue_) internal pure returns (uint104) {
        return safe104((presentValue_ * BASE_INDEX_SCALE) / baseSupplyIndex_);
    }

    function getNowInternal() internal view virtual returns (uint40) {
        if (block.timestamp >= 2 ** 40) revert TimestampTooLarge();
        return uint40(block.timestamp);
    }
}
