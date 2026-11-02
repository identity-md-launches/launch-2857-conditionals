// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {ConditionalsToken} from "../src/ConditionalsToken.sol";

/// @notice Deploys `ConditionalsToken`. The token takes no constructor arguments, so there is
/// nothing to configure: whoever deploys it receives the whole supply.
/// @dev On the IMD launch the factory deploys the token from its bytecode; this script is for
/// local or stand-alone deployments and review. It reads no environment variables, so `deploy()`
/// can be called directly from tests.
contract DeployConditionalsToken is Script {
    /// @notice Deploys the token and returns it. The caller of this function (the broadcaster when
    /// run through `forge script`) is the deployer and receives the supply.
    function deploy() public returns (ConditionalsToken token) {
        token = new ConditionalsToken();
    }

    function run() external returns (ConditionalsToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
