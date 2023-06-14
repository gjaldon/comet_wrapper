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

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));
        // Rewards accrual will not be applied retroactively
        assertEq(cometWrapper.getRewardOwed(alice), 0);
        assertEq(cometWrapper.getRewardOwed(alice), cometRewards.getRewardOwed(cometAddress, alice).owed);

        vm.warp(block.timestamp + 7 days);

        // Rewards accrual in CometWrapper matches rewards accrual in Comet
        assertGt(cometWrapper.getRewardOwed(alice), 0);
        assertEq(cometWrapper.getRewardOwed(alice), cometRewards.getRewardOwed(cometAddress, alice).owed);

        assertGt(cometWrapper.getRewardOwed(bob), 0);
        assertEq(cometWrapper.getRewardOwed(bob), cometRewards.getRewardOwed(cometAddress, bob).owed);

        assertGt(
            cometRewards.getRewardOwed(cometAddress, wrapperAddress).owed,
            cometWrapper.getRewardOwed(bob) + cometWrapper.getRewardOwed(alice)
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
        uint256 rewardsFromComet;
        uint256 wrapperRewards;
        vm.startPrank(alice);
        cometRewards.claim(cometAddress, alice, true);
        rewardsFromComet = comp.balanceOf(alice);
        cometWrapper.claimTo(alice);
        wrapperRewards = comp.balanceOf(alice) - rewardsFromComet;
        vm.stopPrank();

        assertEq(wrapperRewards, rewardsFromComet);

        vm.startPrank(bob);
        cometRewards.claim(cometAddress, bob, true);
        rewardsFromComet = comp.balanceOf(bob);
        cometWrapper.claimTo(bob);
        wrapperRewards = comp.balanceOf(bob) - rewardsFromComet;
        vm.stopPrank();

        assertEq(wrapperRewards, rewardsFromComet);
    }

    function test__accrueRewards() public {
        enableRewardsAccrual();

        vm.prank(cusdcHolder);
        comet.transfer(alice, 10_000e6);

        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(5_000e6, alice);
        vm.stopPrank();

        skip(30 days);
        (uint64 baseTrackingAccrued,) = cometWrapper.userBasic(alice);
        assertEq(baseTrackingAccrued, 0);

        cometWrapper.accrueRewards(alice);
        (baseTrackingAccrued,) = cometWrapper.userBasic(alice);
        assertGt(baseTrackingAccrued, 0);
    }

    function test__accrueRewardsOnTransfer() public {
        enableRewardsAccrual();

        vm.prank(cusdcHolder);
        comet.transfer(alice, 20_000e6);
        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(10_000e6, alice);
        vm.stopPrank();

        skip(30 days);
        vm.prank(alice);
        cometWrapper.transfer(bob, 5_000e6);

        // Alice should have 30 days worth of accrued rewards for her 10K WcUSDC
        assertApproxEqAbs(cometWrapper.getRewardOwed(alice), cometRewards.getRewardOwed(cometAddress, alice).owed, 1000);
        // Bob should have no rewards accrued yet since his balance prior to the transfer was 0
        assertEq(cometWrapper.getRewardOwed(bob), 0);
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
