// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {CometMath} from "./vendor/CometMath.sol";

contract CometHelpers is CometMath {
    uint64 internal constant FACTOR_SCALE = 1e18;
    uint64 internal constant BASE_INDEX_SCALE = 1e15;
    uint64 internal constant BASE_ACCRUAL_SCALE = 1e6;

    error LackAllowance();
    error ZeroShares();
    error ZeroAssets();
    error ZeroAddress();
    error TimestampTooLarge();

    event RewardClaimed(address indexed src, address indexed recipient, address indexed token, uint256 amount);

    function mulFactor(uint256 n, uint256 factor) internal pure returns (uint256) {
        return n * factor / FACTOR_SCALE;
    }

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
