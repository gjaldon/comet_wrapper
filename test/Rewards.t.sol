// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {BaseTest} from "./BaseTest.sol";
import {Deployable, ICometConfigurator, ICometProxyAdmin} from "../src/vendor/ICometConfigurator.sol";
import "forge-std/console.sol";

contract RewardsTest is BaseTest {
    address constant configuratorAddress = 0x316f9708bB98af7dA9c68C1C3b5e79039cD336E3;
    address constant proxyAdminAddress = 0x1EC63B5883C3481134FD50D5DAebc83Ecd2E8779;

    function test__getRewardOwed() public {
        enableRewardsAccrual();

        vm.startPrank(cusdcHolder);
        comet.transfer(alice, 10_000e6);
        comet.transfer(bob, 10_000e6);
        vm.stopPrank();

        vm.startPrank(alice);
        comet.allow(address(cometWrapper), true);
        cometWrapper.deposit(5_000e6, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        comet.allow(address(cometWrapper), true);
        cometWrapper.deposit(5_000e6, bob);
        vm.stopPrank();

        // Assets in CometWrapper should match Comet balance or at least be less by only 1 due to rounding
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));
        assertEq(cometWrapper.underlyingBalance(alice) - 1, comet.balanceOf(alice));
        assertEq(cometWrapper.underlyingBalance(bob) - 1, comet.balanceOf(bob));

        // Rewards accrual will not be applied retroactively
        assertEq(cometWrapper.getRewardOwed(alice), 0);
        assertEq(cometWrapper.getRewardOwed(alice), cometReward.getRewardOwed(cometAddress, alice).owed);

        vm.warp(block.timestamp + 7 days);

        // Rewards accrual in CometWrapper matches rewards accrual in Comet
        assertGt(cometWrapper.getRewardOwed(alice), 0);
        assertEq(cometWrapper.getRewardOwed(alice), cometReward.getRewardOwed(cometAddress, alice).owed);

        assertGt(cometWrapper.getRewardOwed(bob), 0);
        assertEq(cometWrapper.getRewardOwed(bob), cometReward.getRewardOwed(cometAddress, bob).owed);

        assertEq(
            cometWrapper.getRewardOwed(bob) + cometWrapper.getRewardOwed(alice) + 1e12,
            cometReward.getRewardOwed(cometAddress, address(cometWrapper)).owed
        );
    }

    function enableRewardsAccrual() internal {
        address governor = comet.governor();
        ICometConfigurator configurator = ICometConfigurator(configuratorAddress);
        ICometProxyAdmin proxyAdmin = ICometProxyAdmin(proxyAdminAddress);

        vm.startPrank(governor);
        configurator.setBaseTrackingSupplySpeed(cometAddress, 2e14);
        proxyAdmin.deployAndUpgradeTo(Deployable(configuratorAddress), cometAddress);
        vm.stopPrank();
    }
}
