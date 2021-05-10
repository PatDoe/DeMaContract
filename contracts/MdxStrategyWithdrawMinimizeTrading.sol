pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./Interface/IMdexRouter.sol";
import "./Interface/IMdexFactory.sol";
import "./Interface/IMdexPair.sol";
import "./Interface/IWBNB.sol";
import "./Interface/IStrategy.sol";
import "./utils/SafeToken.sol";


contract MdxStrategyWithdrawMinimizeTrading is Ownable, ReentrancyGuard, IStrategy {
    using SafeToken for address;
    using SafeMath for uint256;

    IMdexFactory public factory;
    IMdexRouter public router;
    address public wBNB;

    /// @dev Create a new withdraw minimize trading strategy instance for mdx.
    /// @param _router The mdx router smart contract.
    constructor(IMdexRouter _router) public {
        factory = IMdexFactory(_router.factory());
        router = _router;
        wBNB = _router.WBNB();
    }

    /// @dev Execute worker strategy. Take LP tokens. Return debt token + token want back.
    /// @param user User address to withdraw liquidity.
    /// @param borrowTokens The token user borrow from bank.
    /// @param debts User's debt amount.
    /// @param data Extra calldata information passed along to this strategy.
    function execute(
        address user, 
        address borrowTokens, 
        uint256 /* borrow */, 
        uint256 debts, 
        bytes calldata data
    )
        external
        payable
        nonReentrant
    {
        // 1. Find out lpToken and liquidity.
        // rate will divide 10000. 10000 means all token will be withdrawn.
        // whichWantBack: 
        // 0: token0;
        // 1: token1;
        // 2: token what surplus; 
        // 3: don't back(all repay);
        (address token0, address token1, uint256 rate, uint256 whichWantBack) = 
            abi.decode(data, (address, address, uint256, uint256));

        // is borrowToken is BNB.
        bool isBorrowBNB = borrowToken == address(0);
        require(borrowToken == token0 || borrowToken == token1 || isBorrowBNB, "borrowToken not token0 and token1");
        // the relative token when token0 or token1 is BNB.
        address BNBRelative = address(0);
        {
            if (token0 == address(0)){
                token0 = wBNB;
                BNBRelative = token1;
            }
            if (token1 == address(0)){
                token1 = wBNB;
                BNBRelative = token0;
            }
        }
        address tokenUserWant = whichWantBack == uint(0) ? token0 : token1;

        IMdexPair lpToken = IMdexPair(factory.getPair(token0, token1));
        token0 = lpToken.token0();
        token1 = lpToken.token1();

        {
            lpToken.approve(address(router), uint256(-1));
            router.removeLiquidity(token0, token1, lpToken.balanceOf(address(this)), 0, 0, address(this), now);
        }
        {
            borrowToken = isBorrowBNB ? wBNB : borrowToken;
            address tokenRelative = borrowToken == token0 ? token1 : token0;

            swapIfNeed(borrowToken, tokenRelative, debt);

            if (isBorrowBNB) {
                IWBNB(wBNB).withdraw(debt);
                SafeToken.safeTransferETH(msg.sender, debt);
            } else {
                SafeToken.safeTransfer(borrowToken, msg.sender, debt);
            }
        }

        // 2. swap remaining token to what user want.
        if (whichWantBack != uint(2)) {
            address tokenAnother = tokenUserWant == token0 ? token1 : token0;
            uint256 anotherAmount = tokenAnother.myBalance();
            if(anotherAmount > 0){
                tokenAnother.safeApprove(address(router), 0);
                tokenAnother.safeApprove(address(router), uint256(-1));

                address[] memory path = new address[](2);
                path[0] = tokenAnother;
                path[1] = tokenUserWant;
                router.swapExactTokensForTokens(anotherAmount, 0, path, address(this), now);
            }
        }

        // 3. send all tokens back.
        if (BNBRelative == address(0)) {
            token0.safeTransfer(user, token0.myBalance());
            token1.safeTransfer(user, token1.myBalance());
        } else {
            safeUnWrapperAndAllSend(wBNB, user);
            safeUnWrapperAndAllSend(BNBRelative, user);
        }
    }

    // swap if need.
    // tokenRelative must left at least leftMin amount.
    function swapIfNeed(address borrowToken, address tokenRelative, uint256 debt, uint256 leftMin) internal {
        uint256 borrowTokenAmount = borrowToken.myBalance();
        if (debt > borrowTokenAmount) {
            tokenRelative.safeApprove(address(router), 0);
            tokenRelative.safeApprove(address(router), uint256(-1));

            uint256 remainingDebt = debt.sub(borrowTokenAmount);
            address[] memory path = new address[](2);
            path[0] = tokenRelative;
            path[1] = borrowToken;
            // If there are not enough token, it will raise error. This position could only be liquidate.
            router.swapTokensForExactTokens(remainingDebt, tokenRelative.myBalance(), path, address(this), now);
            require(tokenRelative.myBalance() >= leftMin);
        }
    }

    /// get token balance, if is WBNB un wrapper to BNB and send to 'to'
    function safeUnWrapperAndAllSend(address token, address to) internal {
        uint256 total = SafeToken.myBalance(token);
        if (total > 0) {
            if (token == wBNB) {
                IWBNB(wBNB).withdraw(total);
                SafeToken.safeTransferETH(to, total);
            } else {
                SafeToken.safeTransfer(token, to, total);
            }
        }
    }

    /// @dev Recover ERC20 tokens that were accidentally sent to this smart contract.
    /// @param token The token contract. Can be anything. This contract should not hold ERC20 tokens.
    /// @param to The address to send the tokens to.
    /// @param value The number of tokens to transfer to `to`.
    function recover(address token, address to, uint256 value) external onlyOwner nonReentrant {
        token.safeTransfer(to, value);
    }

    function() external payable {}
}
