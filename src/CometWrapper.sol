// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {CometInterface, TotalsBasic} from "./vendor/CometInterface.sol";
import {CometHelpers} from "./CometHelpers.sol";
import {ICometRewards} from "./vendor/ICometRewards.sol";

/// @notice A vault contract that accepts deposits of a Comet token like cUSDCv3 as an asset
/// and mints shares which are the Wrapped Comet token.
contract CometWrapper is ERC4626, CometHelpers {
    using SafeTransferLib for ERC20;

    struct UserBasic {
        uint104 principal;
        uint64 baseTrackingAccrued;
        uint64 baseTrackingIndex;
    }

    mapping(address => UserBasic) public userBasic;
    mapping(address => uint256) public rewardsClaimed;

    uint40 internal lastAccrualTime;
    uint256 public underlyingPrincipal;

    CometInterface public immutable comet;
    ICometRewards public immutable cometRewards;
    uint256 public immutable trackingIndexScale;
    uint256 internal immutable accrualDescaleFactor;

    constructor(ERC20 _asset, ICometRewards _cometRewards, string memory _name, string memory _symbol)
        ERC4626(_asset, _name, _symbol)
    {
        if (address(_cometRewards) == address(0)) revert ZeroAddress();
        // minimal validation that contract is CometRewards
        _cometRewards.rewardConfig(address(_asset));

        comet = CometInterface(address(_asset));
        lastAccrualTime = getNowInternal();
        cometRewards = _cometRewards;
        trackingIndexScale = comet.trackingIndexScale();
        accrualDescaleFactor = uint64(10 ** asset.decimals()) / BASE_ACCRUAL_SCALE;
    }

    /// @notice Returns total assets managed by the vault
    /// @return total assets
    function totalAssets() public view override returns (uint256) {
        uint64 baseSupplyIndex_ = accruedSupplyIndex(getNowInternal() - lastAccrualTime);
        uint256 principal = underlyingPrincipal;
        return principal > 0 ? presentValueSupply(baseSupplyIndex_, principal) : 0;
    }

    /// @notice Deposits assets into the vault and gets shares (Wrapped Comet token) in return
    /// @param assets The amount of assets to be deposited by the caller
    /// @param receiver The recipient address of the minted shares
    /// @return shares The amount of shares that are minted to the receiver
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        if (assets == 0) revert ZeroAssets();
        shares = previewDeposit(assets);
        if (shares == 0) revert ZeroShares();

        accrueInternal();
        updatePrincipals(receiver, signed256(assets));
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Mints shares (Wrapped Comet) in exchange for Comet tokens
    /// @param shares The amount of shares to be minted for the receive
    /// @param receiver The recipient address of the minted shares
    /// @return assets The amount of assets that are deposited by the caller
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        if (shares == 0) revert ZeroShares();
        assets = previewMint(shares);
        if (assets == 0) revert ZeroAssets();

        accrueInternal();
        updatePrincipals(receiver, signed256(assets));
        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Withdraws assets (Comet) from the vault and burns corresponding shares (Wrapped Comet).
    /// Caller can only withdraw assets from owner if they have been given allowance to.
    /// @param assets The amount of assets to be withdrawn by the caller
    /// @param receiver The recipient address of the withdrawn assets
    /// @param owner The owner of the assets to be withdrawn
    /// @return shares The amount of shares of the owner that are burned
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256 shares) {
        if (assets == 0) revert ZeroAssets();
        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        accrueInternal();
        updatePrincipals(owner, -signed256(assets));

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    /// @notice Redeems shares (Wrapped Comet) in exchange for assets (Wrapped Comet).
    /// Caller can only withdraw assets from owner if they have been given allowance to.
    /// @param shares The amount of shares to be redeemed
    /// @param receiver The recipient address of the withdrawn assets
    /// @param owner The owner of the shares to be redeemed
    /// @return assets The amount of assets that is withdrawn and sent to the receiver
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        if (shares == 0) revert ZeroShares();
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        assets = previewRedeem(shares);
        if (assets == 0) revert ZeroAssets();

        accrueInternal();
        updatePrincipals(owner, -signed256(assets));

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    /// @notice Transfer shares from caller to the recipient
    /// @param to The receiver of the shares (Wrapped Comet) to be transferred
    /// @param amount The amount of shares to be transferred
    /// @return bool Indicates success of the transfer
    function transfer(address to, uint256 amount) public override returns (bool) {
        transferInternal(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfer shares from a specified source to a recipient
    /// @param from The source of the shares to be transferred
    /// @param to The receiver of the shares (Wrapped Comet) to be transferred
    /// @param amount The amount of shares to be transferred
    /// @return bool Indicates success of the transfer
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 allowed = msg.sender == from ? type(uint256).max : allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed < amount) revert LackAllowance();
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        transferInternal(from, to, amount);
        return true;
    }

    function transferInternal(address from, address to, uint256 amount) internal {
        if (amount == 0) revert ZeroTransfer();
        balanceOf[from] -= amount;

        updateTransferPrincipals(from, to, amount);

        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    /// @notice Maximum amount that can be withdrawn
    /// @param account The address to be queried
    /// @return The maximum amount that can be withdrawn from given account
    function maxWithdraw(address account) public view override returns (uint256) {
        return underlyingBalance(account);
    }

    /// @notice Total assets of an account that are managed by this vault
    /// @dev The asset balance is computed from an account's `userBasic.principal` which mirrors how Comet
    /// computes token balances. This is done this way since balances are ever-increasing due to 
    /// interest accrual.
    /// @param account The address to be queried
    /// @return The total amount of assets held by an account
    function underlyingBalance(address account) public view returns (uint256) {
        uint64 baseSupplyIndex_ = accruedSupplyIndex(getNowInternal() - lastAccrualTime);
        uint256 principal = userBasic[account].principal;
        return principal > 0 ? presentValueSupply(baseSupplyIndex_, principal) : 0;
    }

    /// @dev UserBasic.principal is used as the basis for computation of rewards accrual. In Comet,
    /// this is also used for computing interest accrual on the base asset. Balances of users
    /// are also computed from their userBasic.principal. 
    /// This works like [`Comet.updateBasePrincipal`](https://github.com/compound-finance/comet/blob/63e98e5d231ef50c755a9489eb346a561fc7663c/contracts/Comet.sol#L738-L760)
    /// but without the logic for using `trackingBorrowIndex` since principal will never be negative in CometWrapper.
    /// The other difference is that this function also updates the `underlyingPrincipal` which is 
    /// the principal for the whole contract and is similar to `totalSupply` in ERC20.
    function updatePrincipals(address account, int256 balanceChange) internal {
        UserBasic memory basic = userBasic[account];
        uint104 principal = basic.principal;
        (uint64 baseSupplyIndex, uint64 trackingSupplyIndex) = getSupplyIndices();

        if (principal >= 0) {
            uint256 indexDelta = uint256(trackingSupplyIndex - basic.baseTrackingIndex);
            basic.baseTrackingAccrued +=
                safe64(uint104(principal) * indexDelta / trackingIndexScale / accrualDescaleFactor);
        }
        basic.baseTrackingIndex = trackingSupplyIndex;

        if (balanceChange != 0) {
            basic.principal = updatedPrincipal(principal, baseSupplyIndex, balanceChange);
            // Any balance changes should lead to changes in principal
            if (principal == basic.principal) revert NoChangeInPrincipal();
            underlyingPrincipal = updatedPrincipal(underlyingPrincipal, baseSupplyIndex, balanceChange);
        }

        userBasic[account] = basic;
    }

    function updateTransferPrincipals(address from, address to, uint256 shares) internal {
        uint256 _totalAssets = totalAssets();
        uint256 assets = convertToAssets(shares);
        uint104 principalChange = safe104(assets * underlyingPrincipal / _totalAssets);
        userBasic[from].principal -= principalChange;
        userBasic[to].principal += principalChange;
    }

    /// @dev Converts the `principal` to `balance` before adding the signed balance change. The new balance
    /// is the converted back to a `principal` value.
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

    /// @notice Get the reward owed to an account
    /// @dev This is designed to exactly match computation of rewards in Comet
    /// and uses the same configuration as CometRewards. It is a combination of both
    /// [`getRewardOwed`](https://github.com/compound-finance/comet/blob/63e98e5d231ef50c755a9489eb346a561fc7663c/contracts/CometRewards.sol#L110) and [`getRewardAccrued`](https://github.com/compound-finance/comet/blob/63e98e5d231ef50c755a9489eb346a561fc7663c/contracts/CometRewards.sol#L171).
    /// @param account The address to be queried
    /// @return The total amount of rewards owed to an account
    function getRewardOwed(address account) external returns (uint256) {
        ICometRewards.RewardConfig memory config = cometRewards.rewardConfig(address(comet));
        UserBasic memory basic = accrueRewards(account);
        uint256 claimed = rewardsClaimed[account];
        uint256 accrued = basic.baseTrackingAccrued;

        if (config.shouldUpscale) {
            accrued *= config.rescaleFactor;
        } else {
            accrued /= config.rescaleFactor;
        }

        uint256 owed = accrued > claimed ? accrued - claimed : 0;

        return owed;
    }

    /// @notice Claims caller's rewards and sends them to recipient
    /// @dev Always calls CometRewards for updated configs
    /// @param to The address that will receive the rewards
    function claimTo(address to) external {
        address from = msg.sender;
        UserBasic memory basic = accrueRewards(from);
        ICometRewards.RewardConfig memory config = cometRewards.rewardConfig(address(comet));

        uint256 claimed = rewardsClaimed[from];
        uint256 accrued = basic.baseTrackingAccrued;

        if (config.shouldUpscale) {
            accrued *= config.rescaleFactor;
        } else {
            accrued /= config.rescaleFactor;
        }

        if (accrued > claimed) {
            uint256 owed = accrued - claimed;
            rewardsClaimed[from] = accrued;

            emit RewardClaimed(from, to, config.token, owed);
            cometRewards.claimTo(address(comet), address(this), address(this), true);
            ERC20(config.token).safeTransfer(to, owed);
        }
    }

    /// @notice Accrues rewards for the account
    /// @dev Latest trackingSupplyIndex is fetched from Comet so we can compute accurate rewards.
    /// This mirrors the logic for rewards accrual in CometRewards so we properly account for users'
    /// rewards as if they had used Comet directly.
    /// @param account The address to whose rewards we want to accrue
    /// @return The UserBasic struct with updated baseTrackingIndex and/or baseTrackingAccrued fields
    function accrueRewards(address account) public returns (UserBasic memory) {
        UserBasic memory basic = userBasic[account];
        comet.accrueAccount(address(this));
        (, uint64 trackingSupplyIndex) = getSupplyIndices();

        if (basic.principal >= 0) {
            uint256 indexDelta = uint256(trackingSupplyIndex - basic.baseTrackingIndex);
            basic.baseTrackingAccrued +=
                safe64((uint104(basic.principal) * indexDelta) / trackingIndexScale / accrualDescaleFactor);
        }
        basic.baseTrackingIndex = trackingSupplyIndex;
        userBasic[account] = basic;

        return basic;
    }

    /// @dev This returns latest baseSupplyIndex regardless of whether comet.accrueAccount has been called for the
    /// current block. This works like `Comet.accruedInterestedIndices` at but not including computation of
    /// `baseBorrowIndex` since we do not need that index in CometWrapper:
    /// https://github.com/compound-finance/comet/blob/63e98e5d231ef50c755a9489eb346a561fc7663c/contracts/Comet.sol#L383-L394
    function accruedSupplyIndex(uint256 timeElapsed) internal view returns (uint64) {
        (uint64 baseSupplyIndex_,) = getSupplyIndices();
        if (timeElapsed > 0) {
            uint256 utilization = comet.getUtilization();
            uint256 supplyRate = comet.getSupplyRate(utilization);
            baseSupplyIndex_ += safe64(mulFactor(baseSupplyIndex_, supplyRate * timeElapsed));
        }
        return baseSupplyIndex_;
    }

    /// @dev To maintain accuracy, we fetch `baseSupplyIndex` and `trackingSupplyIndex` directly from Comet.
    /// baseSupplyIndex is used on the principal to get the user's latest balance including interest accruals.
    /// trackingSupplyIndex is used to compute for rewards accruals.
    function getSupplyIndices() internal view returns (uint64 baseSupplyIndex_, uint64 trackingSupplyIndex_) {
        TotalsBasic memory totals = comet.totalsBasic();
        baseSupplyIndex_ = totals.baseSupplyIndex;
        trackingSupplyIndex_ = totals.trackingSupplyIndex;
    }
}
