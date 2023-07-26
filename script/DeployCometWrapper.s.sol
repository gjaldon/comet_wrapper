// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {CometWrapper, CometInterface, ICometRewards, CometHelpers, ERC20} from "../src/CometWrapper.sol";

// Deploy with:
// $ source .env
// $ forge script script/DeployCometWrapper.s.sol --rpc-url $GOERLI_RPC_URL --broadcast --verify -vvvv -t --sender address
// Change COMET_ADDRESS and REWARDS_ADDRESS to use the correct addresses for their corresponding CHAIN. Use the correct
// RPC too for the CHAIN you wish to deploy to.

contract DeployCometWrapper is Script {
    address public cometAddr;
    address public rewardsAddr;

    function run() public {
        cometAddr = vm.envAddress("COMET_ADDRESS");
        rewardsAddr = vm.envAddress("REWARDS_ADDRESS");
        vm.startBroadcast();

        console.log("=============================================================");
        console.log("Comet Address:   ", cometAddr);
        console.log("Rewards Address: ", rewardsAddr);
        console.log("=============================================================");

        CometWrapper cometWrapper =
            new CometWrapper(ERC20(cometAddr), ICometRewards(rewardsAddr), "Wrapped Comet USDC", "WcUSDCv3");
        CometInterface comet = CometInterface(cometAddr);

        vm.stopBroadcast();
    }
}
