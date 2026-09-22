// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {IdentityRegistry} from "../src/rwa/IdentityRegistry.sol";
import {ModularCompliance} from "../src/rwa/ModularCompliance.sol";
import {MockUSD} from "../src/rwa/MockUSD.sol";
import {RWASecurityToken} from "../src/rwa/RWASecurityToken.sol";
import {TokenizedFund} from "../src/rwa/TokenizedFund.sol";
import {DvPSettlement} from "../src/rwa/DvPSettlement.sol";

/// @notice Local/demo deployment. A production deployment must split roles across governed accounts.
contract DeployRWAFund is Script {
    function run()
        external
        returns (
            IdentityRegistry registry,
            ModularCompliance compliance,
            MockUSD paymentToken,
            RWASecurityToken shareToken,
            TokenizedFund fund,
            DvPSettlement settlement
        )
    {
        vm.startBroadcast();
        address operator = msg.sender;

        registry = new IdentityRegistry(operator, operator);
        compliance = new ModularCompliance(operator, operator, registry);
        paymentToken = new MockUSD(operator, operator);
        shareToken = new RWASecurityToken("Example RWA Fund Share", "eRWA", operator, operator, registry, compliance);
        fund = new TokenizedFund(operator, operator, operator, paymentToken, shareToken, registry, 1e6);
        settlement = new DvPSettlement();

        compliance.setCountryAllowed(840, true);
        registry.registerInvestor(address(fund), keccak256("FUND_TREASURY"), 840, uint64(block.timestamp + 3650 days));
        shareToken.grantRole(shareToken.AGENT_ROLE(), address(fund));

        vm.stopBroadcast();
    }
}
