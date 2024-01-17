// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/uniswapV2/IUniswapV2Router.sol";
import "./interfaces/uniswapV3/IUniswapV3Router.sol";
import "./interfaces/uniswapV3/IUniswapV3Quoter.sol";
import "./interfaces/curve/ICurveFi.sol";
import "./interfaces/IWETH.sol";

contract TokenSwapper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    event AddUniswapV3Pool(
        address from,
        address to,
        UniswapV3PoolSetting setting
    );
    event RemoveUniswapV3Pool(
        address from,
        address to,
        UniswapV3PoolSetting setting
    );
    event AddCurvePool(address from, address to, CurvePoolSetting setting);
    event RemoveCurvePool(address from, address to, CurvePoolSetting setting);
    event AddTokenSupport(address token);
    event TokenSwap(
        address from,
        address to,
        uint256 amountIn,
        uint256 amountOut
    );

    IUniswapV2Router constant uniswapV2Router =
        IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2Router constant sushiswapRouter =
        IUniswapV2Router(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);
    IUniswapV3Router constant uniswapV3Router =
        IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV3Quoter constant uniswapV3Quoter =
        IUniswapV3Quoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    IWETH constant weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    struct UniswapV3PoolSetting {
        uint24 fee;
    }
    struct CurvePoolSetting {
        address minter;
        bool isV2;
        uint256 i;
        uint256 j;
    }
    enum Protocol {
        UniswapV2,
        Sushiswap,
        UniswapV3,
        Curve
    }
    struct SwapPath {
        address from;
        address to;
        Protocol protocol;
        uint256 index; // only avaialble for uniswap v3 & curve
    }

    mapping(address => mapping(address => UniswapV3PoolSetting[]))
        public uniswapV3Pools; // from => to => pools array

    mapping(address => mapping(address => CurvePoolSetting[]))
        public curvePools; // from => to => pools array

    EnumerableSet.AddressSet internal addressSet;

    receive() external payable {}

    fallback() external payable {}

    constructor() Ownable() {}

    function addUniswapV3Pool(
        address from,
        address to,
        UniswapV3PoolSetting memory setting
    ) external onlyOwner {
        uniswapV3Pools[from][to].push(setting);
        uniswapV3Pools[to][from].push(setting);
        addressSet.add(from);
        addressSet.add(to);

        emit AddUniswapV3Pool(from, to, setting);
    }

    function removeUniswapV3Pool(
        address from,
        address to,
        uint256 index
    ) external onlyOwner {
        UniswapV3PoolSetting memory setting = uniswapV3Pools[from][to][index];
        uniswapV3Pools[from][to][index] = uniswapV3Pools[from][to][
            uniswapV3Pools[from][to].length - 1
        ];
        uniswapV3Pools[from][to].pop();

        emit RemoveUniswapV3Pool(from, to, setting);
    }

    function addCurvePool(
        address from,
        address to,
        CurvePoolSetting memory setting
    ) external onlyOwner {
        curvePools[from][to].push(setting);

        uint256 temp = setting.i;
        setting.i = setting.j;
        setting.j = temp;
        curvePools[to][from].push(setting);

        addressSet.add(from);
        addressSet.add(to);

        emit AddCurvePool(from, to, setting);
    }

    function removeCurvePool(
        address from,
        address to,
        uint256 index
    ) external onlyOwner {
        CurvePoolSetting memory setting = curvePools[from][to][index];
        curvePools[from][to][index] = curvePools[from][to][
            curvePools[from][to].length - 1
        ];
        curvePools[from][to].pop();

        emit RemoveCurvePool(from, to, setting);
    }

    function addTokenSupport(address token) external onlyOwner {
        addressSet.add(token);

        emit AddTokenSupport(token);
    }

    /// @notice this function is not suggested to be called directly
    ///         it's suggested to calculate swap path offchain using calculateBestRoute function
    ///           and execute swap with returned swap path
    function swapETHToUSDT(
        uint256 ethAmount,
        uint256 minUSDTAmount
    ) external payable returns (uint256 usdtAmount) {
        weth.deposit{value: ethAmount}();

        (, SwapPath[] memory path) = calculateBestRoute(ethAmount);
        _executeSwap(path);

        usdtAmount = usdt.balanceOf(address(this));
        require(minUSDTAmount <= usdtAmount, "slippage!");

        usdt.safeTransfer(msg.sender, usdtAmount);

        emit TokenSwap(address(0), address(usdt), ethAmount, usdtAmount);
    }

    function executeSwap(
        uint256 swapAmount,
        SwapPath[] memory path,
        uint256 minOutAmount
    ) external payable returns (uint256 outputAmount) {
        if (path[0].from == address(weth) && msg.value == swapAmount) {
            weth.deposit{value: swapAmount}();
        } else {
            IERC20(path[0].from).safeTransferFrom(
                msg.sender,
                address(this),
                swapAmount
            );
        }

        _executeSwap(path);

        IERC20 output = IERC20(path[path.length - 1].to);
        outputAmount = output.balanceOf(address(this));
        require(minOutAmount <= outputAmount, "slippage!");

        output.safeTransfer(msg.sender, outputAmount);

        emit TokenSwap(path[0].from, address(output), swapAmount, outputAmount);
    }

    function _executeSwap(SwapPath[] memory path) internal {
        for (uint256 i = 0; i < path.length; ++i) {
            uint256 swapAmount = IERC20(path[i].from).balanceOf(address(this));

            if (path[i].protocol == Protocol.UniswapV2) {
                IERC20(path[i].from).approve(
                    address(uniswapV2Router),
                    swapAmount
                );
                address[] memory swapPath = new address[](2);
                swapPath[0] = path[i].from;
                swapPath[1] = path[i].to;
                uniswapV2Router.swapExactTokensForTokens(
                    swapAmount,
                    0,
                    swapPath,
                    address(this),
                    block.timestamp
                );
            }
            if (path[i].protocol == Protocol.Sushiswap) {
                IERC20(path[i].from).approve(
                    address(sushiswapRouter),
                    swapAmount
                );
                address[] memory swapPath = new address[](2);
                swapPath[0] = path[i].from;
                swapPath[1] = path[i].to;
                sushiswapRouter.swapExactTokensForTokens(
                    swapAmount,
                    0,
                    swapPath,
                    address(this),
                    block.timestamp
                );
            }
            if (path[i].protocol == Protocol.UniswapV3) {
                UniswapV3PoolSetting memory setting = uniswapV3Pools[
                    path[i].from
                ][path[i].to][path[i].index];

                IUniswapV3Router.ExactInputSingleParams memory params;
                params.tokenIn = path[i].from;
                params.tokenOut = path[i].to;
                params.fee = setting.fee;
                params.recipient = address(this);
                params.deadline = block.timestamp;
                params.amountIn = swapAmount;
                params.amountOutMinimum = 0;
                params.sqrtPriceLimitX96 = 0;

                IERC20(path[i].from).approve(
                    address(uniswapV3Router),
                    swapAmount
                );

                uniswapV3Router.exactInputSingle(params);
            }
            if (path[i].protocol == Protocol.Curve) {
                CurvePoolSetting memory setting = curvePools[path[i].from][
                    path[i].to
                ][path[i].index];

                IERC20(path[i].from).approve(
                    address(setting.minter),
                    swapAmount
                );

                // We need to finalize this curve swapper logic to support all assets
                // But this will be fine for now, to support ETH -> USDC swap logic
                if (setting.isV2) {
                    ICurveFi(setting.minter).exchange(
                        setting.i,
                        setting.j,
                        swapAmount,
                        0,
                        false
                    );
                } else {
                    ICurveFi(setting.minter).exchange(
                        int128(int256(setting.i)),
                        int128(int256(setting.j)),
                        swapAmount,
                        0
                    );
                }
            }
        }
    }

    /// @notice calculate best route in maximum 2 depth (can be updated if we want)
    /// @dev this can be called offchain, and execute swap with returned swap path
    function calculateBestRoute(
        uint256 ethAmount
    ) public returns (uint256 expectedUsdtAmount, SwapPath[] memory path) {
        (expectedUsdtAmount, path) = _calculateBestRoute0(
            address(weth),
            address(usdt),
            ethAmount
        );

        (
            uint256 expectedUsdtAmount1,
            SwapPath[] memory path1
        ) = _calculateBestRoute1(address(weth), address(usdt), ethAmount);
        if (expectedUsdtAmount1 > expectedUsdtAmount) {
            expectedUsdtAmount = expectedUsdtAmount1;
            path = path1;
        }
    }

    /// @notice calculate best route in 0 depth
    function _calculateBestRoute0(
        address from,
        address to,
        uint256 swapAmount
    ) public returns (uint256 outAmount, SwapPath[] memory path) {
        path = new SwapPath[](1);
        path[0].from = from;
        path[0].to = to;

        {
            // try uniswap V2
            address[] memory swapPath = new address[](2);
            swapPath[0] = from;
            swapPath[1] = to;
            uint256[] memory amountsOut = uniswapV2Router.getAmountsOut(
                swapAmount,
                swapPath
            );
            if (outAmount < amountsOut[amountsOut.length - 1]) {
                outAmount = amountsOut[amountsOut.length - 1];
                path[0].protocol = Protocol.UniswapV2;
            }
        }

        {
            // try sushiswap
            address[] memory swapPath = new address[](2);
            swapPath[0] = from;
            swapPath[1] = to;
            uint256[] memory amountsOut = sushiswapRouter.getAmountsOut(
                swapAmount,
                swapPath
            );
            if (outAmount < amountsOut[amountsOut.length - 1]) {
                outAmount = amountsOut[amountsOut.length - 1];
                path[0].protocol = Protocol.Sushiswap;
            }
        }

        {
            // try uniswapV3
            UniswapV3PoolSetting[] storage settings = uniswapV3Pools[from][to];

            for (uint256 i = 0; i < settings.length; ++i) {
                uint256 amountOut = uniswapV3Quoter.quoteExactInputSingle(
                    from,
                    to,
                    settings[i].fee,
                    swapAmount,
                    0
                );

                if (outAmount < amountOut) {
                    outAmount = amountOut;
                    path[0].protocol = Protocol.UniswapV3;
                    path[0].index = i;
                }
            }
        }

        {
            // try curve
            CurvePoolSetting[] storage settings = curvePools[from][to];

            for (uint256 i = 0; i < settings.length; ++i) {
                uint256 amountOut;
                if (settings[i].isV2) {
                    amountOut = ICurveFi(payable(settings[i].minter)).get_dy(
                        settings[i].i,
                        settings[i].j,
                        swapAmount
                    );
                } else {
                    amountOut = ICurveFi(settings[i].minter).get_dy(
                        int128(int256(settings[i].i)),
                        int128(int256(settings[i].j)),
                        swapAmount
                    );
                }

                if (outAmount < amountOut) {
                    outAmount = amountOut;
                    path[0].protocol = Protocol.Curve;
                    path[0].index = i;
                }
            }
        }
    }

    /// @notice calculate best route in 1 depth
    function _calculateBestRoute1(
        address from,
        address to,
        uint256 swapAmount
    ) public returns (uint256 outAmount, SwapPath[] memory path) {
        path = new SwapPath[](2);

        uint256 length = addressSet.length();
        for (uint256 i = 0; i < length; ++i) {
            address asset = addressSet.at(i);
            if (from == asset || to == asset) {
                continue;
            }

            (
                uint256 outAmount0,
                SwapPath[] memory path0
            ) = _calculateBestRoute0(from, asset, swapAmount);

            (
                uint256 outAmount1,
                SwapPath[] memory path1
            ) = _calculateBestRoute0(asset, to, outAmount0);

            if (outAmount1 > outAmount) {
                outAmount = outAmount1;
                path[0] = path0[0];
                path[1] = path1[0];
            }
        }
    }
}
