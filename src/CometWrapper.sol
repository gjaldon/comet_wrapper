// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {CometInterface, TotalsBasic} from "./vendor/CometInterface.sol";


contract CometWrapper is ERC4626 {
    uint64 internal constant FACTOR_SCALE = 1e18;
    uint64 internal constant BASE_INDEX_SCALE = 1e15;

    uint40 internal lastAccrualTime;
    uint256 public underlyingPrincipal;
    CometInterface immutable comet;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset, _name, _symbol) {
        comet = CometInterface(address(_asset));
        lastAccrualTime = getNowInternal();
    }
    
    function totalAssets() public view override returns (uint256) {
        uint64 baseSupplyIndex_ = accruedSupplyIndex(getNowInternal() - lastAccrualTime);
        uint256 principal = underlyingPrincipal;
        return principal > 0 ? presentValueSupply(baseSupplyIndex_, principal) : 0;
    }

    function accruedSupplyIndex(uint timeElapsed) internal view returns (uint64) {
        (uint64 baseSupplyIndex_,) = getSupplyIndices();
        if (timeElapsed > 0) {
            uint utilization = comet.getUtilization();
            uint supplyRate = comet.getSupplyRate(utilization);
            baseSupplyIndex_ += safe64(mulFactor(baseSupplyIndex_, supplyRate * timeElapsed));
        }
        return baseSupplyIndex_;
    }

    function getSupplyIndices()
        internal
        view
        returns (uint64 baseSupplyIndex_, uint64 trackingSupplyIndex_)
    {
        TotalsBasic memory totals = comet.totalsBasic();
        baseSupplyIndex_ = totals.baseSupplyIndex;
        trackingSupplyIndex_ = totals.trackingSupplyIndex;
    }

    function mulFactor(uint n, uint factor) internal pure returns (uint) {
        return n * factor / FACTOR_SCALE;
    }

    error InvalidUInt64();
    error NegativeNumber();
    error TimestampTooLarge();

    function safe64(uint n) internal pure returns (uint64) {
        if (n > type(uint64).max) revert InvalidUInt64();
        return uint64(n);
    }

    function unsigned104(int104 n) internal pure returns (uint104) {
        if (n < 0) revert NegativeNumber();
        return uint104(n);
    }

     function presentValueSupply(uint64 baseSupplyIndex_, uint256 principalValue_) internal pure returns (uint256) {
        return principalValue_ * baseSupplyIndex_ / BASE_INDEX_SCALE;
    }

    function getNowInternal() virtual internal view returns (uint40) {
        if (block.timestamp >= 2**40) revert TimestampTooLarge();
        return uint40(block.timestamp);
    }
}
