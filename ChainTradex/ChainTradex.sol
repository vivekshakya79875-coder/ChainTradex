// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ChainTradeX Project Contract
 * @dev A decentralized trading platform for peer-to-peer token exchanges
 */
contract Project is ReentrancyGuard, Ownable {
    
    // Trade structure
    struct Trade {
        address creator;
        address tokenA;
        address tokenB;
        uint256 amountA;
        uint256 amountB;
        uint256 deadline;
        bool isActive;
    }
    
    // State variables
    mapping(uint256 => Trade) public trades;
    mapping(address => uint256[]) public userTrades;
    uint256 public tradeCounter;
    uint256 public platformFee = 25; // 0.25% (25/10000)
    
    // Constructor
    constructor() Ownable(msg.sender) {
        // Contract deployer becomes the owner
    }
    
    // Events
    event TradeCreated(
        uint256 indexed tradeId,
        address indexed creator,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 deadline
    );
    
    event TradeExecuted(
        uint256 indexed tradeId,
        address indexed executor,
        address indexed creator
    );
    
    event TradeCancelled(
        uint256 indexed tradeId,
        address indexed creator
    );
    
    /**
     * @dev Creates a new trade order
     * @param _tokenA Address of token being offered
     * @param _tokenB Address of token being requested  
     * @param _amountA Amount of tokenA to trade
     * @param _amountB Amount of tokenB requested
     * @param _deadline Unix timestamp for trade expiration
     * @return tradeId Unique identifier for the created trade
     */
    function createTrade(
        address _tokenA,
        address _tokenB,
        uint256 _amountA,
        uint256 _amountB,
        uint256 _deadline
    ) external nonReentrant returns (uint256 tradeId) {
        require(_tokenA != address(0) && _tokenB != address(0), "Invalid token");
        require(_tokenA != _tokenB, "Same token not allowed");
        require(_amountA > 0 && _amountB > 0, "Amount must be > 0");
        require(_deadline > block.timestamp, "Invalid deadline");
        
        IERC20 tokenA = IERC20(_tokenA);
        require(tokenA.balanceOf(msg.sender) >= _amountA, "Insufficient balance");
        require(tokenA.allowance(msg.sender, address(this)) >= _amountA, "Insufficient allowance");
        
        // Transfer tokens to contract
        require(tokenA.transferFrom(msg.sender, address(this), _amountA), "Transfer failed");
        
        // Create trade
        tradeCounter++;
        tradeId = tradeCounter;
        
        trades[tradeId] = Trade({
            creator: msg.sender,
            tokenA: _tokenA,
            tokenB: _tokenB,
            amountA: _amountA,
            amountB: _amountB,
            deadline: _deadline,
            isActive: true
        });
        
        userTrades[msg.sender].push(tradeId);
        
        emit TradeCreated(tradeId, msg.sender, _tokenA, _tokenB, _amountA, _amountB, _deadline);
        return tradeId;
    }
    
    /**
     * @dev Executes an existing trade order
     * @param _tradeId ID of the trade to execute
     */
    function executeTrade(uint256 _tradeId) external nonReentrant {
        require(_tradeId > 0 && _tradeId <= tradeCounter, "Invalid trade ID");
        Trade storage trade = trades[_tradeId];
        require(trade.isActive, "Trade not active");
        require(block.timestamp <= trade.deadline, "Trade expired");
        require(trade.creator != msg.sender, "Cannot execute own trade");
        
        IERC20 tokenA = IERC20(trade.tokenA);
        IERC20 tokenB = IERC20(trade.tokenB);
        
        require(tokenB.balanceOf(msg.sender) >= trade.amountB, "Insufficient balance");
        require(tokenB.allowance(msg.sender, address(this)) >= trade.amountB, "Insufficient allowance");
        
        // Calculate fee
        uint256 feeA = (trade.amountA * platformFee) / 10000;
        uint256 feeB = (trade.amountB * platformFee) / 10000;
        
        // Update trade status
        trade.isActive = false;
        
        // Execute transfers
        require(tokenB.transferFrom(msg.sender, trade.creator, trade.amountB - feeB), "Transfer failed");
        require(tokenA.transfer(msg.sender, trade.amountA - feeA), "Transfer failed");
        
        // Transfer fees to owner
        if (feeA > 0) require(tokenA.transfer(owner(), feeA), "Fee transfer failed");
        if (feeB > 0) require(tokenB.transferFrom(msg.sender, owner(), feeB), "Fee transfer failed");
        
        emit TradeExecuted(_tradeId, msg.sender, trade.creator);
    }
    
    /**
     * @dev Cancels an active trade order (only by creator)
     * @param _tradeId ID of the trade to cancel
     */
    function cancelTrade(uint256 _tradeId) external nonReentrant {
        require(_tradeId > 0 && _tradeId <= tradeCounter, "Invalid trade ID");
        Trade storage trade = trades[_tradeId];
        require(trade.creator == msg.sender, "Not trade creator");
        require(trade.isActive, "Trade not active");
        
        // Update status
        trade.isActive = false;
        
        // Return tokens to creator
        IERC20(trade.tokenA).transfer(trade.creator, trade.amountA);
        
        emit TradeCancelled(_tradeId, msg.sender);
    }
    
    // View functions
    function getTrade(uint256 _tradeId) external view returns (Trade memory) {
        return trades[_tradeId];
    }
    
    function getUserTrades(address _user) external view returns (uint256[] memory) {
        return userTrades[_user];
    }
    
    function getActiveTradesCount() external view returns (uint256 count) {
        for (uint256 i = 1; i <= tradeCounter; i++) {
            if (trades[i].isActive && block.timestamp <= trades[i].deadline) {
                count++;
            }
        }
    }
    
    // Owner functions
    function updatePlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 500, "Fee cannot exceed 5%");
        platformFee = _newFee;
    }
}
