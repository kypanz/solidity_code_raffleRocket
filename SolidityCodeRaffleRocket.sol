// "SPDX-License-Identifier: MIT"
// Code by "kypanz" github : https://github.com/kypanz
// Linkedin : https://www.linkedin.com/in/ismael-zamora-199516171/
// I love what i do, no matter what <3

/*
    What this code do ?
    - Create, manage and participate in multiple raffles at the same time
    - You can finish a raffle only if the 80% percent of the tickets are selled
    - Wait "X" days to the finish raffle
    - If the raffle is finished but the owner of the raffle dont finish using the function "finishRaffle",
      Any user "participant" can get back the price of that ticket
    - I add a anoter functions "admin" functions in case of emergency to block the functions for security reasons
*/


// Adding Chainlink VRF for random numbers
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

pragma solidity ^0.8.0;

contract BeeTeamLotteryX is VRFConsumerBaseV2 {

    // Needed for Chainlink subscription VRF
    VRFCoordinatorV2Interface COORDINATOR;
    uint64 s_subscriptionId;
    address vrfCoordinator = 0x6168499c0cFfCaCD319c818142124B7A15E857ab; // Rinkeby testnet
    bytes32 keyHash = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc; // Rinkeby values
    uint32 callbackGasLimit = 300000;
    uint16 requestConfirmations = 3;
    uint32 numWords =  1;
    uint256[] public s_randomWords;
    uint256 public s_requestId;
    address s_owner;

    // Admin | options
    address beeTeamAdmin;
    uint256 minPercentageForRafflesWithdraw;
    bool securityBlockedStatus = false;
    string securityReason;

    constructor(uint64 subscriptionId) VRFConsumerBaseV2(vrfCoordinator) {
        // for chainlink random numbers
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        s_owner = msg.sender;
        s_subscriptionId = subscriptionId;

        // for the raffle system
        beeTeamAdmin = msg.sender;
        minPercentageForRafflesWithdraw = 80;
    }

    // Status of the Raffle
    enum statusRaffle { InProgress, Finished, Closed }

    // The Raffle
    struct Raffle{

        // Part one | Values returned in functions, see below
        address ownerOfRaffle;
        address winner;
        string nameOfRaffle;
        uint rewardAmount;
        bool statusRewarded;
        uint priceTicket;
        uint maxTickets;

        // Part two | Values returned in functions, see below
        statusRaffle status;
        uint256 counterTickets;
        uint256[] tickets;
        address[] participants;
        uint counterParticipants;
        uint256 initialDate;
        uint256 x_days;
    
    }

    // Users and tickets
    struct Tickets{
        uint256[] tickets; // todos mis tickets asociados a un raffle id
    }

    struct User{
        uint256[] myOwnRafflesId;
        uint256[] rafflesId;
        mapping(uint256 => Tickets) tickets;
        uint256 counterTickets;
    }

    // This structure is used for que Queue of raffles that need a random number
    struct QueueRaffle {
        uint256 idRaffle;
        uint256 ticketsCounter;
    }

    // For raffle
    QueueRaffle[] lastRaffleIds; // <-- this is gonna be used for identify the winners of raffles => last raffle finished
    uint256 counterQueue = 0; // <-- this gonna be used to index the queue list to see what values need to change and in what raffle

    // Mappings
    mapping(address => User) users;
    mapping(uint256 => Raffle) public raffles;

    // Modifiers
    modifier isBlocked(){
        require(securityBlockedStatus == false,'This function are blocked for security reasons');
        _;
    }
    modifier checkIfTheRaffleExist(uint256 _idRaffle){
        require(raffles[_idRaffle].ownerOfRaffle != 0x0000000000000000000000000000000000000000,'This raffle not exist');
        _;
    }
    modifier checkIfRaffleFinish(uint256 _idRaffle){
        // Check if the raffle finished in date time
        require(block.timestamp - raffles[_idRaffle].initialDate > ( raffles[_idRaffle].x_days * 1 days ) ,'This raffle are not in finish date');
        _;
    }
    modifier onlyAdmin() {
        require(msg.sender == beeTeamAdmin,'Only beeTeamAdmin can run this function');
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == s_owner);
        _;
    }

    modifier adminSecurity(){
        require(securityBlockedStatus == false,'This action is blocked for security reasons');
        _;
    }


    // TicketCounter
    uint256 raffleNumber = 1;

    // Users can create all Raffles that they want
    function createRaffle(string memory _nameRaffle, uint256 _rewardAmount, uint256 _priceTicket, uint256 _maxTickets, uint256 _days) isBlocked() public payable {
        
        require(msg.value > 0,'You need to send MTR');
        require( (_rewardAmount * 10 ** 18) == msg.value - ( 2 * 10 ** 18 ), 'send the same MTR at rewardAmount + 2 MTR more');
        require(_days >= 1,'Minimun Day 1 , Maximun day 7');
        require(_priceTicket >= 1,'Minimun price ticket 1 MTR');
        require(_maxTickets >= 10,'Minimun tickets to sell - 10');
        

        // Setting the data for the raffle
        raffles[raffleNumber].ownerOfRaffle = msg.sender;
        raffles[raffleNumber].nameOfRaffle = _nameRaffle;
        raffles[raffleNumber].rewardAmount = _rewardAmount;
        raffles[raffleNumber].priceTicket = _priceTicket;
        raffles[raffleNumber].maxTickets = _maxTickets;
        raffles[raffleNumber].status = statusRaffle.InProgress;
        raffles[raffleNumber].counterTickets = 0;
        raffles[raffleNumber].initialDate = block.timestamp;
        raffles[raffleNumber].x_days = _days;

        // Setting the data for the user
        users[msg.sender].myOwnRafflesId.push(raffleNumber);

        // Adding the new raffle number
        raffleNumber++;

    }

    // Get information of some raffle here | You need to use the Part one and part Two functions to get all the data
    function getRaffleByIdPartOne(uint256 _id) public view returns(
        address ownerOfRaffle,
        address winner,
        string memory nameOfRaffle,
        uint rewardAmount,
        bool statusRewarded,
        uint priceTicket,
        uint maxTickets
        ) {
        return(
            raffles[_id].ownerOfRaffle,
            raffles[_id].winner,
            raffles[_id].nameOfRaffle,
            raffles[_id].rewardAmount,
            raffles[_id].statusRewarded,
            raffles[_id].priceTicket,
            raffles[_id].maxTickets
        );
    }

    function getRaffleByIdPartTwo(uint256 _id) public view returns(
        statusRaffle status,
        uint counterTickets,
        address[] memory _participants,
        uint256[] memory _tickets,
        uint256 initialDate,
        uint256 x_days
    ){
        return(
            raffles[_id].status,
            raffles[_id].counterTickets,
            raffles[_id].participants,
            raffles[_id].tickets,
            raffles[_id].initialDate,
            raffles[_id].x_days
        );
    }

    function getMyInfo() public view returns(uint256[] memory _myOwnRafflesId, uint256[] memory _myRafflesId, uint256[] memory _myTickets){
        _myOwnRafflesId = users[msg.sender].myOwnRafflesId;
        _myRafflesId = users[msg.sender].rafflesId;
        for(uint i = 0; i < users[msg.sender].rafflesId.length; i++){
            _myTickets = users[msg.sender].tickets[  uint256(users[msg.sender].rafflesId[i])  ].tickets;
        }
    }

    // Here you can buy a ticket for some tickets for specific raffle, anyone can buy exept the owner of the raffle
    // You can buy some many tickets that you want
    function buyTicket(uint256 _idRaffle) isBlocked() checkIfTheRaffleExist(_idRaffle) public payable {

        // Check if the raffle buy all the tickets
        require(raffles[_idRaffle].maxTickets != raffles[_idRaffle].counterTickets,'All tickets are selled');
        
        // You need to send the same MTR at the price per ticket
        require(msg.value == ( raffles[_idRaffle].priceTicket * 10 ** 18 ),'You need to send the price in MTR');

        // You cant buy tickets in your own raffle
        require(msg.sender != raffles[_idRaffle].ownerOfRaffle,'You cant buy tickets in your own raffle');

        // Adding the tickets
        raffles[_idRaffle].counterTickets++;

        // Adding the tickets and the participant
        raffles[_idRaffle].participants.push(msg.sender);
        raffles[_idRaffle].tickets.push( raffles[_idRaffle].counterTickets );

        // Adding the ticket and the raffle id to the user information
        users[msg.sender].rafflesId.push(_idRaffle);
        users[msg.sender].tickets[_idRaffle].tickets.push( raffles[_idRaffle].counterTickets );
    
    }

    // This function is runned for owner and participants
    function finishRaffle(uint256 _idRaffle) isBlocked() checkIfTheRaffleExist(_idRaffle) checkIfRaffleFinish(_idRaffle) public {

        require(raffles[_idRaffle].status == statusRaffle.InProgress,'This raffle are finished or closed');
        require(raffles[_idRaffle].ownerOfRaffle == msg.sender,'You need to be the owner of this raffle');
        require(raffles[_idRaffle].counterTickets > gettingTheMinimunTickets(raffles[_idRaffle].maxTickets),'You dont sell the minimun percentage of the raffle, you can close it');
        
        // Set the last raffle finished
        lastRaffleIds.push( QueueRaffle({ idRaffle : _idRaffle, ticketsCounter : raffles[_idRaffle].counterTickets }) );

        // Getting the winner
        requestRandomWords();

    }

    // Close the raffle
    function closeRaffle(uint256 _idRaffle) checkIfTheRaffleExist(_idRaffle) checkIfRaffleFinish(_idRaffle) public {
        require(raffles[_idRaffle].ownerOfRaffle == msg.sender,'You are not owner of this raffle');
        require(raffles[_idRaffle].status != statusRaffle.Closed,'You already close this raffle');
        raffles[_idRaffle].status = statusRaffle.Closed;
        payable(msg.sender).transfer((raffles[_idRaffle].rewardAmount) * 1 ether ); // <-- the multiplication * 1 ether is needed to convert wei to ether value ;)
    }

    // This functions can be used for participants if the owner of the raffle dont finish the raffle after 3 days more than expected finished date
    function getMyTicketPriceBack(uint256 _idRaffle, uint256 _ticketId) isBlocked()  public {

        require(raffles[_idRaffle].statusRewarded == false, 'This raffle are already rewarded, you cant get the ticket back');
        require(block.timestamp - raffles[_idRaffle].initialDate > ( raffles[_idRaffle].x_days + 3 * 1 days ) ,'You need to wait 3 days after finish date'); // nota : enable this

        // Logic for back ticket price to the participant
        bool iAmOwnerOfThatTicket = false;
        bool isDone = false;
        for(uint256 i =0; i< raffles[_idRaffle].tickets.length; i++){
            if(msg.sender == raffles[_idRaffle].participants[i] && _ticketId == raffles[_idRaffle].tickets[i]) {
                removeParticipantByIndex(_idRaffle,i);
                removeFromMyTickets(_idRaffle,_ticketId);
                iAmOwnerOfThatTicket = true;
                isDone = true;
            }
        }
        require(iAmOwnerOfThatTicket == true,'You are not owner of that ticket');

        // Decrease the ticket counter
        raffles[_idRaffle].counterTickets = raffles[_idRaffle].counterTickets - 1;

        // Refunding for the participant
        if(isDone == true) payable(address(msg.sender)).transfer(raffles[_idRaffle].priceTicket * 1 ether);

    }

    // Remove from my info
    function removeFromMyTickets(uint256 _idRaffle, uint256 _ticket) private {

       for(uint256 i =0; i < users[msg.sender].rafflesId.length; i++){
        
            if( _idRaffle == users[msg.sender].rafflesId[i] ){
                for(uint256 j =0; j < users[msg.sender].tickets[ users[msg.sender].rafflesId[i] ].tickets.length; j++ ){
                    if( _ticket == users[msg.sender].tickets[ users[msg.sender].rafflesId[i] ].tickets[j] ){
                        
                        // removing raffleid
                        users[msg.sender].rafflesId[i] = users[msg.sender].rafflesId[ users[msg.sender].rafflesId.length - 1 ];

                        // removing ticket
                        users[msg.sender].tickets[ users[msg.sender].rafflesId[i] ].tickets[j] = users[msg.sender].tickets[ users[msg.sender].rafflesId[i] ].tickets[ users[msg.sender].tickets[ users[msg.sender].rafflesId[i] ].tickets.length - 1 ];
                    
                        // done
                        users[msg.sender].tickets[ users[msg.sender].rafflesId[i] ].tickets.pop();
                        users[msg.sender].rafflesId.pop();
                        break;
                    }
                }
            }
       
       }
    }

    // Remove participant
    function removeParticipantByIndex(uint256 _raffleId,uint index) private {
        // Step one
        raffles[_raffleId].participants[index] = raffles[_raffleId].participants[ raffles[_raffleId].participants.length - 1 ];
        raffles[_raffleId].tickets[index] = raffles[_raffleId].tickets[ raffles[_raffleId].tickets.length - 1 ];
        // Step two
        raffles[_raffleId].participants.pop();
        raffles[_raffleId].tickets.pop();
    }

    // This function is used to get the right minimun percentage for withdraw
    function gettingTheMinimunTickets(uint256 _amount) private view returns(uint256) {
        return ( minPercentageForRafflesWithdraw * _amount ) / 100;
    }
    
    // Here are setting the minimun percentage
    function settingTheMinimunPercentage(uint256 _newPercentage) onlyAdmin() public {
        minPercentageForRafflesWithdraw = _newPercentage;
    }

    // Blocking functions for security reason
    function blockFunctions(string memory _reason) onlyAdmin() public {
        (securityBlockedStatus == true) ? securityBlockedStatus = false : securityBlockedStatus = true;
        securityReason = _reason;
    }

    // Getting the reason of the block
    function statusOfBlockedFunctions() public view returns(bool, string memory){
        return(securityBlockedStatus,securityReason);
    }

    // Get the balance of this contract here | Status of Smart Contract Raffle - BeeHive Team
    function getSmartContractBalance() public view returns(uint256){
        return address(this).balance;
    }

    // Get index of the last raffle
    function getRaffles() public view returns(uint256) {
        return raffleNumber;
    }


    // Chainlink Functions | This function generate the request for a random number
    function requestRandomWords() private {
        // Will revert if subscription is not set and funded.
        s_requestId = COORDINATOR.requestRandomWords(
        keyHash,
        s_subscriptionId,
        requestConfirmations,
        callbackGasLimit,
        numWords
        );
    }


    // This function is used when recive the result of a random number
    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        s_randomWords = randomWords;
        uint256 s_randomRange = (randomWords[0] % lastRaffleIds[counterQueue].ticketsCounter); // 0 - tickets of last raffle finished;
        winningProcess(lastRaffleIds[counterQueue].idRaffle,s_randomRange); // <-- set the winner passing the lastRaffle request and the range of winners of that raffle
        counterQueue++; // <-- this actualizate the queue index to see what is the next raffle that is need to be done
    }

    // This function set the winner after recive the random number
    function winningProcess(uint256 _idRaffle, uint256 _winnerTicket) private {
        // Setting the winner
        raffles[_idRaffle].winner = raffles[_idRaffle].participants[_winnerTicket];
        raffles[_idRaffle].status = statusRaffle.Finished;
        raffles[_idRaffle].statusRewarded = true;
        payable(address(raffles[_idRaffle].participants[_winnerTicket])).transfer(raffles[_idRaffle].rewardAmount * 1 ether); // 1

        // Reward the owner of the raffle
        uint256 ticketsSelled = raffles[_idRaffle].counterTickets;
        uint256 priceTicket = raffles[_idRaffle].priceTicket;
        payable(address(raffles[_idRaffle].ownerOfRaffle)).transfer((ticketsSelled * priceTicket) * 1 ether); // 1
    }
    
}
