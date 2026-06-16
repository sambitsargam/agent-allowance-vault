// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AgentAllowanceVault} from "../src/AgentAllowanceVault.sol";

/// @notice Deploys an AgentAllowanceVault for a given ERC20 token.
/// @dev    Usage:
///         forge script script/DeployVault.s.sol:DeployVault \
///           --rpc-url atlantic --broadcast \
///           --private-key $PRIVATE_KEY \
///           --sig "run(address)" <TOKEN_ADDRESS>
contract DeployVault is Script {
    function run(address token) external returns (address vault) {
        vm.startBroadcast();
        AgentAllowanceVault v = new AgentAllowanceVault(token);
        vm.stopBroadcast();

        vault = address(v);
        console2.log("AgentAllowanceVault deployed at:", vault);
        console2.log("Custodied token:", token);
        console2.log("Owner:", v.owner());
    }
}
