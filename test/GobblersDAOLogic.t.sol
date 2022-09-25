// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

import 'forge-std/Test.sol';
import { GobblersDAOLogicV2 } from '../src/GobblersDAOLogic.sol';
import { GobblersDAOProxyV2 } from '../src/GobblersDAOProxy.sol';
import { GobblersDAOStorageV2, GobblersDAOStorageV1Adjusted } from '../src/GobblersDAOInterfaces.sol';
import { GobblersDAOExecutor } from '../src/GobblersDAOExecutor.sol';

contract GobblersDAOLogicV2Test is Test, DeployUtils {
    GobblersDAOLogicV2 daoLogic;
    GobblersDAOLogicV2 daoProxy;
    GobblersToken nounsToken;
    GobblersDAOExecutor timelock = new GobblersDAOExecutor(address(1), TIMELOCK_DELAY);
    address vetoer = address(0x3);
    address admin = address(0x4);
    address noundersDAO = address(0x5);
    address minter = address(0x6);
    address proposer = address(0x7);
    uint256 votingPeriod = 6000;
    uint256 votingDelay = 1;
    uint256 proposalThresholdBPS = 200;

    event NewPendingVetoer(address oldPendingVetoer, address newPendingVetoer);
    event NewVetoer(address oldVetoer, address newVetoer);
    event Withdraw(uint256 amount, bool sent);

    function setUp() public virtual {
        daoLogic = new GobblersDAOLogicV2();

        GobblersDescriptorV2 descriptor = _deployAndPopulateV2();

        nounsToken = new GobblersToken(noundersDAO, minter, descriptor, new GobblersSeeder(), IProxyRegistry(address(0)));

        daoProxy = GobblersDAOLogicV2(
            payable(
                new GobblersDAOProxyV2(
                    address(timelock),
                    address(nounsToken),
                    vetoer,
                    admin,
                    address(daoLogic),
                    votingPeriod,
                    votingDelay,
                    proposalThresholdBPS,
                    GobblersDAOStorageV2.DynamicQuorumParams({
                        minQuorumVotesBPS: 200,
                        maxQuorumVotesBPS: 2000,
                        quorumCoefficient: 10000
                    })
                )
            )
        );

        vm.prank(address(timelock));
        timelock.setPendingAdmin(address(daoProxy));
        vm.prank(address(daoProxy));
        timelock.acceptAdmin();
    }
}

contract UpdateVetoerTest is GobblersDAOLogicV2Test {
    function setUp() public override {
        super.setUp();
    }

    function test_setPendingVetoer_failsIfNotCurrentVetoer() public {
        vm.expectRevert(GobblersDAOLogicV2.VetoerOnly.selector);
        daoProxy._setPendingVetoer(address(0x1234));
    }

    function test_setPendingVetoer_updatePendingVetoer() public {
        assertEq(daoProxy.pendingVetoer(), address(0));

        address pendingVetoer = address(0x3333);

        vm.prank(vetoer);
        vm.expectEmit(true, true, true, true);
        emit NewPendingVetoer(address(0), pendingVetoer);
        daoProxy._setPendingVetoer(pendingVetoer);

        assertEq(daoProxy.pendingVetoer(), pendingVetoer);
    }

    function test_onlyPendingVetoerCanAcceptNewVetoer() public {
        address pendingVetoer = address(0x3333);

        vm.prank(vetoer);
        daoProxy._setPendingVetoer(pendingVetoer);

        vm.expectRevert(GobblersDAOLogicV2.PendingVetoerOnly.selector);
        daoProxy._acceptVetoer();

        vm.prank(pendingVetoer);
        vm.expectEmit(true, true, true, true);
        emit NewVetoer(vetoer, pendingVetoer);
        daoProxy._acceptVetoer();

        assertEq(daoProxy.vetoer(), pendingVetoer);
        assertEq(daoProxy.pendingVetoer(), address(0x0));
    }

    function test_burnVetoPower_failsIfNotVetoer() public {
        vm.expectRevert('GobblersDAO::_burnVetoPower: vetoer only');
        daoProxy._burnVetoPower();
    }

    function test_burnVetoPower_setsVetoerToZero() public {
        vm.prank(vetoer);
        vm.expectEmit(true, true, true, true);
        emit NewVetoer(vetoer, address(0));
        daoProxy._burnVetoPower();

        assertEq(daoProxy.vetoer(), address(0));
    }

    function test_burnVetoPower_setsPendingVetoerToZero() public {
        address pendingVetoer = address(0x3333);

        vm.prank(vetoer);
        daoProxy._setPendingVetoer(pendingVetoer);

        vm.prank(vetoer);
        vm.expectEmit(true, true, true, true);
        emit NewPendingVetoer(pendingVetoer, address(0));
        daoProxy._burnVetoPower();

        vm.prank(pendingVetoer);
        vm.expectRevert(GobblersDAOLogicV2.PendingVetoerOnly.selector);
        daoProxy._acceptVetoer();

        assertEq(daoProxy.pendingVetoer(), address(0));
    }
}

contract CancelProposalTest is GobblersDAOLogicV2Test {
    uint256 proposalId;

    function setUp() public override {
        super.setUp();

        vm.prank(minter);
        nounsToken.mint();

        vm.prank(minter);
        nounsToken.transferFrom(minter, proposer, 1);

        vm.roll(block.number + 1);

        vm.prank(proposer);
        address[] memory targets = new address[](1);
        targets[0] = address(0x1234);
        uint256[] memory values = new uint256[](1);
        values[0] = 100;
        string[] memory signatures = new string[](1);
        signatures[0] = '';
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = '';
        proposalId = daoProxy.propose(targets, values, signatures, calldatas, 'my proposal');
    }

    function testProposerCanCancelProposal() public {
        vm.prank(proposer);
        daoProxy.cancel(proposalId);

        assertEq(uint256(daoProxy.state(proposalId)), uint256(GobblersDAOStorageV1Adjusted.ProposalState.Canceled));
    }

    function testNonProposerCantCancel() public {
        vm.expectRevert('GobblersDAO::cancel: proposer above threshold');
        daoProxy.cancel(proposalId);

        assertEq(uint256(daoProxy.state(proposalId)), uint256(GobblersDAOStorageV1Adjusted.ProposalState.Pending));
    }

    function testAnyoneCanCancelIfProposerVotesBelowThreshold() public {
        vm.prank(proposer);
        nounsToken.transferFrom(proposer, address(0x9999), 1);

        vm.roll(block.number + 1);

        daoProxy.cancel(proposalId);

        assertEq(uint256(daoProxy.state(proposalId)), uint256(GobblersDAOStorageV1Adjusted.ProposalState.Canceled));
    }
}

contract WithdrawTest is GobblersDAOLogicV2Test {
    function setUp() public override {
        super.setUp();
    }

    function test_withdraw_worksForAdmin() public {
        vm.deal(address(daoProxy), 100 ether);
        uint256 balanceBefore = admin.balance;

        vm.expectEmit(true, true, true, true);
        emit Withdraw(100 ether, true);

        vm.prank(admin);
        (uint256 amount, bool sent) = daoProxy._withdraw();

        assertEq(amount, 100 ether);
        assertTrue(sent);
        assertEq(admin.balance - balanceBefore, 100 ether);
    }

    function test_withdraw_revertsForNonAdmin() public {
        vm.expectRevert(GobblersDAOLogicV2.AdminOnly.selector);
        daoProxy._withdraw();
    }
}
