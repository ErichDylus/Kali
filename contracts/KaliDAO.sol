// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import './KaliDAOtoken.sol';
import './utils/Multicall.sol';
import './utils/NFThelper.sol';
import './utils/ReentrancyGuard.sol';
import './IKaliDAOextension.sol';

/// @notice Simple gas-optimized DAO core module.
contract KaliDAO is KaliDAOtoken, Multicall, NFThelper, ReentrancyGuard {
    /*///////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event NewProposal(address indexed proposer, uint256 indexed proposal, string description);

    event ProposalCancelled(address indexed proposer, uint256 indexed proposal);

    event ProposalSponsored(address indexed sponsor, uint256 indexed proposal);
    
    event VoteCast(address indexed voter, uint256 indexed proposal, bool indexed approve);

    event ProposalProcessed(uint256 indexed proposal);

    /*///////////////////////////////////////////////////////////////
                            DAO STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public proposalCount;

    uint32 public votingPeriod;

    uint8 public quorum; // 1-100

    uint8 public supermajority; // 1-100
    
    bytes32 public constant VOTE_HASH = 
        keccak256('SignVote(address signer,uint256 proposal,bool approve)');
    
    mapping(address => bool) public extensions;

    mapping(uint256 => Proposal) public proposals;

    mapping(ProposalType => VoteType) public proposalVoteTypes;
    
    mapping(uint256 => mapping(address => bool)) public voted;

    mapping(uint256 => bool) public passed;

    enum ProposalType {
        MINT, // add membership
        BURN, // revoke membership
        CALL, // call contracts
        PERIOD, // set `votingPeriod`
        QUORUM, // set `quorum`
        SUPERMAJORITY, // set `supermajority`
        TYPE, // set `VoteType` to `ProposalType`
        PAUSE, // flip membership transferability
        EXTENSION // flip `extensions` whitelisting
    }

    enum VoteType {
        SIMPLE_MAJORITY,
        SIMPLE_MAJORITY_QUORUM_REQUIRED,
        SUPERMAJORITY,
        SUPERMAJORITY_QUORUM_REQUIRED
    }

    struct Proposal {
        ProposalType proposalType;
        string description;
        address[] accounts; // member(s) being added/kicked; account(s) receiving payload
        uint256[] amounts; // value(s) to be minted/burned/spent; gov setting [0]
        bytes[] payloads; // data for CALL proposals
        uint96 yesVotes;
        uint96 noVotes;
        uint32 creationTime;
        address proposer;
    }

    /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function init(
        string memory name_,
        string memory symbol_,
        bool paused_,
        address[] memory extensions_,
        address[] memory voters_,
        uint256[] memory shares_,
        uint32 votingPeriod_,
        uint8[11] memory govSettings_
    ) public payable nonReentrant virtual {
        require(votingPeriod == 0, 'INITIALIZED');

        require(votingPeriod_ > 0 && votingPeriod_ <= 365 days, 'VOTING_PERIOD_BOUNDS');
        
        require(govSettings_[0] <= 100, 'QUORUM_MAX');
        
        require(govSettings_[1] > 51 && govSettings_[1] <= 100, 'SUPERMAJORITY_BOUNDS');

        KaliDAOtoken._init(name_, symbol_, paused_, voters_, shares_);

        // this is reasonably safe from overflow because incrementing `i` loop beyond
        // 'type(uint256).max' is exceedingly unlikely compared to optimization benefits
        unchecked {
            for (uint256 i; i < extensions_.length; i++) {
                extensions[extensions_[i]] = true;
            }
        }
        
        votingPeriod = votingPeriod_;
        
        quorum = govSettings_[0];
        
        supermajority = govSettings_[1];

        // set initial vote types
        proposalVoteTypes[ProposalType.MINT] = VoteType(govSettings_[2]);

        proposalVoteTypes[ProposalType.BURN] = VoteType(govSettings_[3]);

        proposalVoteTypes[ProposalType.CALL] = VoteType(govSettings_[4]);

        proposalVoteTypes[ProposalType.PERIOD] = VoteType(govSettings_[5]);
        
        proposalVoteTypes[ProposalType.QUORUM] = VoteType(govSettings_[6]);
        
        proposalVoteTypes[ProposalType.SUPERMAJORITY] = VoteType(govSettings_[7]);

        proposalVoteTypes[ProposalType.TYPE] = VoteType(govSettings_[8]);
        
        proposalVoteTypes[ProposalType.PAUSE] = VoteType(govSettings_[9]);
        
        proposalVoteTypes[ProposalType.EXTENSION] = VoteType(govSettings_[10]);
    }

    /*///////////////////////////////////////////////////////////////
                            PROPOSAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function getProposalArrays(uint256 proposal) public view virtual returns (
        address[] memory accounts, 
        uint256[] memory amounts, 
        bytes[] memory payloads
    ) {
        Proposal storage prop = proposals[proposal];
        
        (accounts, amounts, payloads) = (prop.accounts, prop.amounts, prop.payloads);
    }

    function propose(
        ProposalType proposalType,
        string calldata description,
        address[] calldata accounts,
        uint256[] calldata amounts,
        bytes[] calldata payloads
    ) public nonReentrant virtual returns (uint256 proposal) {
        require(accounts.length == amounts.length && amounts.length == payloads.length, 'NO_ARRAY_PARITY');
        
        require(accounts.length <= 10, 'ARRAY_MAX');

        bool selfSponsor;

        // if member is making proposal, include sponsorship
        if (balanceOf[msg.sender] > 0) selfSponsor = true;
        
        if (proposalType == ProposalType.PERIOD) require(amounts[0] <= 365 days, 'VOTING_PERIOD_BOUNDS');
        
        if (proposalType == ProposalType.QUORUM) require(amounts[0] <= 100, 'QUORUM_MAX');
        
        if (proposalType == ProposalType.SUPERMAJORITY) require(amounts[0] > 51 && amounts[0] <= 100, 'SUPERMAJORITY_BOUNDS');

        if (proposalType == ProposalType.TYPE) require(amounts[0] <= 8 && amounts[1] <= 3, 'TYPE_MAX');

        proposal = proposalCount;

        proposals[proposal] = Proposal({
            proposalType: proposalType,
            description: description,
            accounts: accounts,
            amounts: amounts,
            payloads: payloads,
            yesVotes: 0,
            noVotes: 0,
            creationTime: selfSponsor ? safeCastTo32(block.timestamp) : 0,
            proposer: msg.sender
        });
        
        // this is reasonably safe from overflow because incrementing `proposalCount` beyond
        // 'type(uint256).max' is exceedingly unlikely compared to optimization benefits
        unchecked {
            proposalCount++;
        }

        emit NewProposal(msg.sender, proposal, description);
    }

    function cancelProposal(uint256 proposal) public nonReentrant virtual {
        Proposal storage prop = proposals[proposal];

        require(msg.sender == prop.proposer, 'NOT_PROPOSER');

        require(prop.creationTime == 0, 'SPONSORED');

        delete proposals[proposal];

        emit ProposalCancelled(msg.sender, proposal);
    }

    function sponsorProposal(uint256 proposal) public nonReentrant virtual {
        Proposal storage prop = proposals[proposal];

        require(balanceOf[msg.sender] > 0, 'NOT_MEMBER');

        require(prop.proposer != address(0), 'NOT_PROPOSAL');

        require(prop.creationTime == 0, 'SPONSORED');

        prop.creationTime = safeCastTo32(block.timestamp);

        emit ProposalSponsored(msg.sender, proposal);
    } 

    function vote(uint256 proposal, bool approve) public nonReentrant virtual {
        _vote(msg.sender, proposal, approve);
    }
    
    function voteBySig(
        address signer, 
        uint256 proposal, 
        bool approve, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) public nonReentrant virtual {
        // validate signature elements
        bytes32 digest =
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            VOTE_HASH,
                            signer,
                            proposal,
                            approve
                        )
                    )
                )
            );
            
        address recoveredAddress = ecrecover(digest, v, r, s);
        
        require(recoveredAddress == signer, 'INVALID_SIG');
        
        _vote(signer, proposal, approve);
    }
    
    function _vote(
        address signer, 
        uint256 proposal, 
        bool approve
    ) internal virtual {
        require(balanceOf[signer] > 0, 'NOT_MEMBER');

        require(!voted[proposal][signer], 'ALREADY_VOTED');
        
        Proposal storage prop = proposals[proposal];
        
        // this is safe from overflow because `votingPeriod` is capped so it will not combine
        // with unix time to exceed 'type(uint256).max'
        unchecked {
            require(block.timestamp <= prop.creationTime + votingPeriod, 'VOTING_ENDED');
        }

        uint96 weight = getPriorVotes(signer, prop.creationTime);
        
        // this is safe from overflow because `yesVotes` and `noVotes` are capped by `totalSupply`
        // which is checked for overflow in `KaliDAOtoken` contract
        unchecked { 
            if (approve) {
                prop.yesVotes += weight;
            } else {
                prop.noVotes += weight;
            }
        }
        
        voted[proposal][signer] = true;
        
        emit VoteCast(signer, proposal, approve);
    }

    function processProposal(uint256 proposal) public nonReentrant virtual returns (bytes[] memory results) {
        // we want underflow in this case to allow for first proposal
        unchecked {
            require(proposals[proposal - 1].creationTime == 0, 'PREV_NOT_PROCESSED');
        }

        Proposal storage prop = proposals[proposal];

        delete proposals[proposal];

        require(prop.creationTime > 0, 'PROCESSED');
        
        // this is safe from overflow because `votingPeriod` is capped so it will not combine
        // with unix time to exceed 'type(uint256).max'
        unchecked {
            require(block.timestamp > prop.creationTime + votingPeriod, 'VOTING_NOT_ENDED');
        }

        VoteType voteType = proposalVoteTypes[prop.proposalType];

        bool didProposalPass = _countVotes(voteType, prop.yesVotes, prop.noVotes);
        
        if (didProposalPass) {
            passed[proposal] = true;

            // this is reasonably safe from overflow because incrementing `i` loop beyond
            // 'type(uint256).max' is exceedingly unlikely compared to optimization benefits
            unchecked {
                if (prop.proposalType == ProposalType.MINT) 
                    for (uint256 i; i < prop.accounts.length; i++) {
                        _mint(prop.accounts[i], prop.amounts[i]);
                        
                        _moveDelegates(address(0), delegates(prop.accounts[i]), prop.amounts[i]);
                    }
                    
                if (prop.proposalType == ProposalType.BURN) 
                    for (uint256 i; i < prop.accounts.length; i++) {
                        _burn(prop.accounts[i], prop.amounts[i]);
                        
                        _moveDelegates(delegates(prop.accounts[i]), address(0), prop.amounts[i]);
                    }
                    
                if (prop.proposalType == ProposalType.CALL) 
                    for (uint256 i; i < prop.accounts.length; i++) {
                        results = new bytes[](prop.accounts.length);
                        
                        (, bytes memory result) = prop.accounts[i].call{value: prop.amounts[i]}
                            (prop.payloads[i]);
                        
                        results[i] = result;
                    }
                    
                // governance settings
                if (prop.proposalType == ProposalType.PERIOD) 
                    if (prop.amounts[0] > 0) votingPeriod = uint32(prop.amounts[0]);
                
                if (prop.proposalType == ProposalType.QUORUM) 
                    if (prop.amounts[0] > 0) quorum = uint8(prop.amounts[0]);
                
                if (prop.proposalType == ProposalType.SUPERMAJORITY) 
                    if (prop.amounts[0] > 0) supermajority = uint8(prop.amounts[0]);
                
                if (prop.proposalType == ProposalType.TYPE) 
                    proposalVoteTypes[ProposalType(prop.amounts[0])] = VoteType(prop.amounts[1]);
                
                if (prop.proposalType == ProposalType.PAUSE) 
                    _togglePause();
                
                if (prop.proposalType == ProposalType.EXTENSION) 
                    extensions[prop.accounts[0]] = !extensions[prop.accounts[0]];
            }
        }

        emit ProposalProcessed(proposal);
    }

    function _countVotes(
        VoteType voteType,
        uint256 yesVotes,
        uint256 noVotes
    ) internal view virtual returns (bool didProposalPass) {
        // rule out any failed quorums
        if (voteType == VoteType.SIMPLE_MAJORITY_QUORUM_REQUIRED || voteType == VoteType.SUPERMAJORITY_QUORUM_REQUIRED) {
            uint256 minVotes = (totalSupply * quorum) / 100;
            
            // this is safe from overflow because `yesVotes` and `noVotes` are capped by `totalSupply`
            // which is checked for overflow in `KaliDAOtoken` contract
            unchecked {
                uint256 votes = yesVotes + noVotes;

                if (votes < minVotes) return false;
            }
        }
        
        // simple majority
        if (voteType == VoteType.SIMPLE_MAJORITY || voteType == VoteType.SIMPLE_MAJORITY_QUORUM_REQUIRED) {
            if (yesVotes > noVotes) return true;
        // super majority
        } else {
            // example: 7 yes, 2 no, supermajority = 66
            // ((7+2) * 66) / 100 = 5.94; 7 yes will pass
            uint256 minYes = ((yesVotes + noVotes) * supermajority) / 100;

            if (yesVotes >= minYes) return true;
        }
    }
    
    /*///////////////////////////////////////////////////////////////
                            UTILITIES 
    //////////////////////////////////////////////////////////////*/
    
    receive() external payable virtual {}
    
    function callExtension(
        address extension, 
        uint256 amount, 
        bytes calldata extensionData,
        bool mint
    ) public payable nonReentrant virtual returns (uint256 amountOut) {
        require(extensions[extension], 'NOT_EXTENSION');
        
        amountOut = IKaliDAOextension(extension).callExtension{value: msg.value}
            (msg.sender, amount, extensionData);
        
        if (mint) {
            if (amountOut > 0) _mint(msg.sender, amountOut); 
        } else {
            if (amountOut > 0) _burn(msg.sender, amount);
        }
    }
}
