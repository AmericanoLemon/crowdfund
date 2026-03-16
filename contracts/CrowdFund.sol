// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract CrowdFund {
    enum CampaignStatus {
        Active,
        Successful,
        Failed,
        Claimed
    }

    struct Campaign {
        uint256 campaignId;
        address creator;
        string title;
        string description;
        uint256 goalAmount;
        uint256 currentAmount;
        uint256 deadline;
        uint256 createdAt;
        CampaignStatus status;
        uint256 contributorCount;
    }

    uint256 public campaignCounter;
    uint256 public constant MIN_GOAL = 0.01 ether;
    uint256 public constant MAX_DURATION = 90 days;
    uint256 public constant MIN_DURATION = 1 days;
    uint256 public constant MIN_CONTRIBUTION = 0.001 ether;

    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => mapping(address => uint256)) public contributions;
    mapping(uint256 => mapping(address => bool)) public hasContributed;
    mapping(address => uint256[]) public creatorCampaigns;

    event CampaignCreated(uint256 indexed campaignId, address indexed creator, string title, uint256 goalAmount, uint256 deadline);
    event ContributionMade(uint256 indexed campaignId, address indexed contributor, uint256 amount, uint256 totalRaised);
    event CampaignSuccessful(uint256 indexed campaignId, uint256 totalRaised);
    event FundsClaimed(uint256 indexed campaignId, address indexed creator, uint256 amount);
    event RefundIssued(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    event CampaignFailed(uint256 indexed campaignId, uint256 totalRaised, uint256 goalAmount);

    modifier campaignExists(uint256 _campaignId){
        require(campaigns[_campaignId].campaignId != 0, "Campaign doesnt exist!");
        _;
    }

    modifier onlyCreator(uint256 _campaignId){
        require(campaigns[_campaignId].creator == msg.sender, "Only creator can perform this action!");
        _;
    } 

    modifier onlyContributor(uint256 _campaignId){
        require(hasContributed[_campaignId][msg.sender], "You are not contributor!");
        _;
    }

    modifier isActive(uint256 _campaignId){
        require(campaigns[_campaignId].status == CampaignStatus.Active, "Campaign is not active!");
        _;
    }

    function createCampaign(string memory _title, string memory _description, uint256 _goalAmount, uint256 _durationDays) public {
        require(_goalAmount >= MIN_GOAL, "Minimum goal fund is 0.01 ETH");
        require(
            _durationDays >= MIN_DURATION && _durationDays <= MAX_DURATION,
            "Duration must be between 1 and 90 days"
        );
        campaignCounter++;
        uint256 deadline = block.timestamp + (_durationDays * 1 days);
        campaigns[campaignCounter] = Campaign({
            campaignId: campaignCounter,
            creator: msg.sender,
            title: _title,
            description: _description,
            goalAmount: _goalAmount,
            currentAmount: 0,
            deadline: deadline,
            createdAt: block.timestamp,
            status: CampaignStatus.Active,
            contributorCount: 0
        });
        creatorCampaigns[msg.sender].push(campaignCounter);
        emit CampaignCreated(campaignCounter, msg.sender, _title, _goalAmount, deadline);
    }

    function contribute(uint256 _campaignId) public payable campaignExists(_campaignId) isActive(_campaignId) {
        require(block.timestamp < campaigns[_campaignId].deadline, "Campaign has ended!");
        require(msg.value >= MIN_CONTRIBUTION, "Minimum contribution is 0.001 ETH");
        require(msg.sender != campaigns[_campaignId].creator, "Creator cannot contribute!");

        if(!hasContributed[_campaignId][msg.sender]){
            hasContributed[_campaignId][msg.sender] = true;
            campaigns[_campaignId].contributorCount++;
        }

        campaigns[_campaignId].currentAmount += msg.value;
        contributions[_campaignId][msg.sender] += msg.value;

        emit ContributionMade(_campaignId, msg.sender, msg.value, campaigns[_campaignId].currentAmount);
        
        if(campaigns[_campaignId].currentAmount >= campaigns[_campaignId].goalAmount){
            campaigns[_campaignId].status = CampaignStatus.Successful;
            emit CampaignSuccessful(_campaignId, campaigns[_campaignId].currentAmount);
        }
    }

    function claimFunds(uint256 _campaignId) public campaignExists(_campaignId) onlyCreator(_campaignId) {
        Campaign storage campaign = campaigns[_campaignId];
        require(campaign.status == CampaignStatus.Successful, "Campaign is not successful!");
        campaign.status = CampaignStatus.Claimed;
        uint256 amount = campaign.currentAmount;

        (bool success, ) = campaign.creator.call{value: amount}("");
        require(success, "Failed to send funds to creator");

        emit FundsClaimed(_campaignId, campaign.creator, amount);
    }

    function refund(uint256 _campaignId) public campaignExists(_campaignId) {
        Campaign storage campaign = campaigns[_campaignId];
        require(campaign.status == CampaignStatus.Failed, "Campaign is not failed!");
        require(contributions[_campaignId][msg.sender] > 0, "You doesnt have any contribution!");

        uint256 amount = contributions[_campaignId][msg.sender];
        contributions[_campaignId][msg.sender] = 0;
        campaign.contributorCount--;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Failed to refund!");

        emit RefundIssued(_campaignId, msg.sender, amount);
    }

    function checkCampaign(uint256 _campaignId) public campaignExists(_campaignId) {
        Campaign storage campaign = campaigns[_campaignId];
        require(campaign.status == CampaignStatus.Active, "Campaign not active");
        require(block.timestamp >= campaign.deadline, "Campaign still running");

        uint256 current = campaign.currentAmount;
        uint256 goal = campaign.goalAmount;

        if (current >= goal) {
            campaign.status = CampaignStatus.Successful;
            emit CampaignSuccessful(_campaignId, current);
        } else {
            campaign.status = CampaignStatus.Failed;
            emit CampaignFailed(_campaignId, current, goal);
        }
    }

    function getCampaignDetails(uint256 _campaignId) public view campaignExists(_campaignId) returns (Campaign memory) {
        return campaigns[_campaignId];
    }

    function getMyContribution(uint256 _campaignId) public view campaignExists(_campaignId) returns (uint256) {
        return contributions[_campaignId][msg.sender];
    }

    function getMyCampaigns() public view returns (uint256[] memory) {
        return creatorCampaigns[msg.sender];
    }

    function getTimeRemaining(uint256 _campaignId) public view campaignExists(_campaignId) returns (uint256) {
        if (block.timestamp >= campaigns[_campaignId].deadline) {
            return 0;
        }
        return campaigns[_campaignId].deadline - block.timestamp;
    }

    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }
}