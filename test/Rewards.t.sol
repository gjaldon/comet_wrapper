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

        // Alice and Bob have same amount of funds in both CometWrapper and Comet
        vm.startPrank(cusdcHolder);
        comet.transfer(alice, 10_000e6);
        comet.transfer(bob, 10_000e6);
        vm.stopPrank();

        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(5_000e6, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(5_000e6, bob);
        vm.stopPrank();

        // Assets in CometWrapper should match Comet balance or at least be less by only 1 due to rounding
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));
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
            cometReward.getRewardOwed(cometAddress, wrapperAddress).owed
        );
    }

    function test__claimTo() public {
        enableRewardsAccrual();

        // Alice and Bob have same amount of funds in both CometWrapper and Comet
        vm.startPrank(cusdcHolder);
        comet.transfer(alice, 10_000e6);
        comet.transfer(bob, 10_000e6);
        vm.stopPrank();

        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(5_000e6, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(5_000e6, bob);
        vm.stopPrank();

        skip(30 days);

        // Accrued rewards in CometWrapper matches accrued rewards in Comet
        uint256 cometRewards;
        uint256 wrapperRewards;
        vm.startPrank(alice);
        cometReward.claim(cometAddress, alice, true);
        cometRewards = comp.balanceOf(alice);
        cometWrapper.claimTo(alice);
        wrapperRewards = comp.balanceOf(alice) - cometRewards;
        vm.stopPrank();
        
        assertEq(wrapperRewards, cometRewards);

        vm.startPrank(bob);
        cometReward.claim(cometAddress, bob, true);
        cometRewards = comp.balanceOf(bob);
        cometWrapper.claimTo(bob);
        wrapperRewards = comp.balanceOf(bob) - cometRewards;
        vm.stopPrank();

        assertEq(wrapperRewards, cometRewards);

        // After all rewards are claimed, contract must have either 0 or negligible dust left
        assertLe(comp.balanceOf(wrapperAddress), 1e12);
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
