// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {CometWrapper, CometInterface, ICometRewards, CometHelpers, ERC20} from "../src/CometWrapper.sol";

contract DeployCometWrapper is Script {
    // Goerli addresses
    address constant COMET = 0x3EE77595A8459e93C2888b13aDB354017B198188;
    address constant REWARDS = 0xef9e070044d62C38D2e316146dDe92AD02CF2c2c;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        CometWrapper cometWrapper =
            new CometWrapper(ERC20(COMET), ICometRewards(REWARDS), "Wrapped Comet USDC", "WcUSDCv3");
        CometInterface comet = CometInterface(COMET);
        comet.allow(address(cometWrapper), true);
        cometWrapper.initialize();

        vm.stopBroadcast();
    }
}
