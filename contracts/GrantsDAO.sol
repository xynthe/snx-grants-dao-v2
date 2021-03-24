//SPDX-License-Identifier: Unlicense
pragma solidity ^0.5.16;

import "hardhat/console.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";

contract GrantsDAO is Ownable {
    using SafeMath for uint;
    using SafeERC20 for ERC20;

    /// @notice The owner is the multisig that the grants DAO member control
    address public owner;

    /// @notice Global state to store the count of proposals
    uint256 public proposalCount;

    ///@notice State given to a proposal
    enum ProposalState {PROPOSED, ACCEPTED, COMPLETED, REJECTED}

    ///@notice A proposal struct, containing all the required fields for a proposal
    struct Proposal {
        string title;
        string description;
        string url;
        uint256 milestoneCount;
        uint256[] milestoneAmounts;
        uint256 currentMilestone;
        uint256 totalAmount;
        address proposer;
        address receiver;
        address token;
        uint256 createdAt;
        uint256 modifiedAt;
        ProposalState state;
        string[] tags;
    }

    ///@notice A mapping that maps a proposalId to the proposal (proposalId will be based on the proposalCount global variable)
    mapping(uint256 => Proposal) public proposals;

    /** EVENTS */

    event NewProposal(uint256 indexed proposalNumber, address receiver, uint256 totalAmount);

    event AcceptProposal(uint256 indexed proposalNumber);

    event RejectProposal(uint256 proposalNumber, string reason);

    event CompleteProposal(uint256 proposal, uint256 paidOut, IERC20 token);

    event MilestoneCompleted(
        uint256 proposalNumber,
        uint256 completedMilestone,
        uint256 totalMilestones,
        uint256 paid,
        address token
    );

    /**
     * @notice Contract is created by a deployer who then sets the grantsDAO multisig to be the owner
     */
    constructor() public {
        owner = msg.sender;
    }

    /**
     * @notice Called by proposers (gDAO or community) to propose funding for a project.
     * Emits NewProposal event.
     * @param _title The title of the proposal
     * @param _description The description of the proposal
     * @param _hash The url of the full proposal which should live on ipfs, written in markdown
     * @param _milestoneCount The number of milestones in this proposal
     * @param _milestoneAmounts An array of the milestone payment amounts, where the zero-based index corresponds to each milestone (0 = first milestone)
     * @param _receiver The receiver of the proposal payments
     * @param _token The token contract address which the payment will be made in (ERC20 only)
     * @return The proposal number for reference
     */
    function createProposal(
        string memory _title,
        string memory _description,
        string memory _url,
        uint256 _milestoneCount,
        uint256[] memory _milestoneAmounts,
        address _receiver,
        address _token,
        string[] tags
    ) public returns (uint256) {
        require(_ > 0, "Amount must be greater than 0");
        require(_receiver != address(0), "Receiver cannot be zero address");
        require(_milestoneCount == _milestoneAmounts.length, "Milestone count must match milestone amounts array length");

        uint256 _counter = counter;
        counter = _counter.add(1);

        uint _totalAmount;

        for (uint i = 0; i < _milestoneAmounts.length; i++) {
            _totalAmount += _milestoneAmounts[i];
        }

        proposals[_counter] = Proposal(
            _title,
            _description,
            _url,
            _milestoneCount,
            _milestoneAmounts,
            _totalAmount,
            msg.sender,
            _receiver,
            _token,
            now,
            now,
            ProposalState.PROPOSED,
            tags
        );

        emit NewProposal(_counter, _receiver, _totalAmount);

        return _counter;
    }

    /**
     * @notice Called by the grantsDAO multisig, sets a proposal to APPROVED to signify that the proposal is being funded
     * Emits AcceptProposal event.
     * @param _proposalId The proposal id to mark as accepted
     */
    function acceptProposal(uint256 _proposalId) onlyOwner() {
        proposals[_proposal].ProposalState = ProposalState.ACCEPTED;

        emit AcceptProposal(_proposalId);
    }

    /**
     * @notice Called by the grantsDAO multisig, pays the next milestone amount
     * Emits MilestoneCompleted event.
     * @param _proposalId The proposal id to complete a milestone on
     */
    function completeMilestone(uint256 _proposalId) onlyOwner() {
        Proposal _currentProposal = proposal[_proposalId];

        IERC20 token = IERC20(_currentProposal.token);

        uint256 amount = _currentProposal.milestoneAmounts[_currentProposal.currentMilestone];

        token.safeTransfer(_currentProposal.receiver, amount);

        _currentProposal.currentMilestone += 1;

        emit MilestoneCompleted(
            _proposalId,
            _currentProposal.currentMilestone,
            _currentProposal.milestoneCount,
            amount,
            _currentProposal.token
        );

        if (_currentProposal.currentMilestone == _currentProposal.milestoneCount - 1) {
            _currentProposal.ProposalState = ProposalState.COMPLETED;

            emit CompleteProposal(_proposalId, _currentProposal.totalAmount, _currentProposal.token);
        }
    }

    /**
     * @notice Called by the grantsDAO multisig, pays out the remainding funds on a proposal.
     * Emits MilestoneCompleted event.
     * @param _proposalId The proposal id to complete a milestone on
     */
    function emergencyPayout(uint256 _proposalId) onlyOwner() {
        Proposal _currentProposal = proposal[_proposalId];
        IERC20 token = IERC20(_currentProposal.token);

        uint256 amount;

        for (uint i = _currentProposal.currentMilestone; i < _currentProposal.milestoneCount; i++) {
            amount += _currentProposal.milestoneAmounts[i];
        }

        token.safeTransfer(_currentProposal.receiver, amount);

        _currentProposal.ProposalState = ProposalState.COMPLETED;
        _currentProposal.currentMilestone = _currentProposal.milestoneCount - 1;

        emit CompleteProposal(_proposalId, _currentProposal.totalAmount, _currentProposal.token);
    }

    /**
     * @notice Called by the grantsDAO multisig, sets a proposal to rejected state
     * Emits RejectProposal event.
     * @param _proposalId The proposal id to complete a milestone on
     * @param _reason A description on why a proposal was rejected
     */
    function rejectProposal(uint256 _proposalId, string memory _reason) onlyOwner() {
        Proposal _currentProposal = proposal[_proposalId];

        _currentProposal.ProposalState = ProposalState.REJECTED;

        emit RejectProposal(_proposalId, _reason);
    }

    /**
     * @notice Allows the owner to withdraw any tokens from the contract
     * @param _receiver The address to receive tokens
     * @param _amount The amount to withdraw
     * @param _erc20 The address of the ERC20 token being transferred
     *
     */
    function withdrawERC20(
        address _receiver,
        uint256 _amount,
        address _erc20
    ) external onlyOwner() {
        IERC20 token = IERC20(token);
        require(_amount <= token.balanceOf(this), "Insufficient funds to withdraw");

        token.safeTransfer(receiver, amount);
    }
}
