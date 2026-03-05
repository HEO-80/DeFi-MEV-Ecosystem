// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "aave-v3-core/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import "aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol";

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract FlashLoanBot is FlashLoanSimpleReceiverBase {
    address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    ISwapRouter public immutable router;

    constructor(address _addressProvider)
        FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider))
    {
        router = ISwapRouter(SWAP_ROUTER);
    }

    function solicitarPrestamo(uint256 cantidad) external {
        POOL.flashLoanSimple(address(this), DAI, cantidad, "", 0);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        
        // 1. Calculamos la deuda total (Lo que hay que devolver sí o sí)
        uint256 deudaTotal = amount + premium;

        // --- 2. ZONA DE TRADING (Intentamos ganar dinero) ---
        
        // A. DAI -> WETH
        IERC20(DAI).approve(address(router), amount);
        uint256 wethComprado = router.exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: DAI,
            tokenOut: WETH,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        }));

        // B. WETH -> DAI
        IERC20(WETH).approve(address(router), wethComprado);
        uint256 daiFinal = router.exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: DAI,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: wethComprado,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        }));

        // --- 3. VÁLVULA DE SEGURIDAD (PROFIT CHECK) ---
        // Si lo que tengo ahora es MENOS de lo que debo... ¡ABORTO LA MISIÓN!
        
        if (daiFinal < deudaTotal) {
            // Este mensaje saldrá en rojo en la terminal
            revert("ESTRATEGIA FALLIDA: No hay beneficio, cancelando para no perder dinero.");
        }

        // Si llegamos aquí, es que hemos ganado dinero (o al menos empatado)
        
        // 4. Devolver el préstamo
        IERC20(asset).approve(address(POOL), deudaTotal);

        return true;
    }
}