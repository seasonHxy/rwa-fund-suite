// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../../src/rwa/IdentityRegistry.sol";
import {ModularCompliance} from "../../src/rwa/ModularCompliance.sol";
import {RWASecurityToken} from "../../src/rwa/RWASecurityToken.sol";
import {RWATokenHandler} from "./handlers/RWATokenHandler.sol";

contract RWASecurityTokenInvariantTest is Test {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant REGISTRAR = address(0xB0B);
    address internal constant COMPLIANCE_OFFICER = address(0xC011);
    address internal constant AGENT = address(0xA63);
    uint16 internal constant US = 840;
    uint256 internal constant INITIAL_BALANCE = 1_000 ether;

    IdentityRegistry internal registry;
    ModularCompliance internal compliance;
    RWASecurityToken internal token;
    RWATokenHandler internal handler;
    address[] internal actors;

    function setUp() public {
        registry = new IdentityRegistry(ADMIN, REGISTRAR);
        compliance = new ModularCompliance(ADMIN, COMPLIANCE_OFFICER, registry);
        token = new RWASecurityToken("Invariant RWA", "iRWA", ADMIN, AGENT, registry, compliance);

        vm.prank(COMPLIANCE_OFFICER);
        compliance.setCountryAllowed(US, true);

        actors.push(address(0x1001));
        actors.push(address(0x1002));
        actors.push(address(0x1003));

        for (uint256 i; i < actors.length; ++i) {
            vm.prank(REGISTRAR);
            registry.registerInvestor(
                actors[i], keccak256(abi.encode("investor", i)), US, uint64(block.timestamp + 365 days)
            );
            vm.prank(AGENT);
            token.mint(actors[i], INITIAL_BALANCE);
        }

        uint256 initialSupply = INITIAL_BALANCE * actors.length;
        handler = new RWATokenHandler(token, AGENT, actors, initialSupply);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.mint.selector;
        selectors[1] = handler.burn.selector;
        selectors[2] = handler.transfer.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    function invariant_TrackedBalancesEqualTotalSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, token.totalSupply());
    }

    function invariant_GhostSupplyMatchesTokenSupply() public view {
        assertEq(handler.initialSupply() + handler.ghostMinted() - handler.ghostBurned(), token.totalSupply());
    }

    function invariant_FrozenAmountNeverExceedsBalance() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertLe(token.frozenTokens(actors[i]), token.balanceOf(actors[i]));
        }
    }

    function invariant_AllTrackedActorsRemainVerified() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertTrue(registry.isVerified(actors[i]));
        }
    }
}

