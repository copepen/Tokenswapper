const chai = require("chai");
const { solidity } = require("ethereum-waffle");
const { ethers } = require("hardhat");
const { expect } = chai;

chai.use(solidity);

const USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
const WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
const USDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
const DAI = "0x6b175474e89094c44da98b954eedeac495271d0f";
const WBTC = "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599";

describe("Token Swapper", () => {
  let owner;
  let tokenSwapper;
  let usdt;

  const swapAmount = ethers.utils.parseEther("20");
  before(async () => {
    [owner] = await ethers.getSigners();

    const TokenSwapper = await ethers.getContractFactory("TokenSwapper");
    tokenSwapper = await TokenSwapper.deploy();
    await tokenSwapper.deployed();

    usdt = await ethers.getContractAt("IERC20", USDT);

    await tokenSwapper.addTokenSupport(WETH); // weth
    await tokenSwapper.addTokenSupport(USDC); // usdc
    await tokenSwapper.addTokenSupport(USDT); // usdt
    await tokenSwapper.addTokenSupport(DAI); // dai
    await tokenSwapper.addTokenSupport(WBTC); // wbtc
  });

  describe("should swap 20 ETH to USDT (uniswap v2, sushiswap)", () => {
    it("20 ETH -> USDT: direct swap (uniswap v2, sushiswap)", async () => {
      const balanceBefore = await usdt.balanceOf(owner.address);

      const res = await tokenSwapper.callStatic.calculateBestRoute(swapAmount);

      await tokenSwapper.swapETHToUSDT(swapAmount, 0, {
        value: swapAmount,
      });

      console.log(
        "20 ETH -> ",
        (Number(res.expectedUsdtAmount) / 1e6).toString(),
        "USDT, path: ",
        res.path.toString()
      );

      expect(await usdt.balanceOf(owner.address)).to.equal(
        balanceBefore.add(res.expectedUsdtAmount)
      );
    });

    it("20 ETH -> USDT: execute (uniswap v2, sushiswap)", async () => {
      const balanceBefore = await usdt.balanceOf(owner.address);

      const res = await tokenSwapper.callStatic.calculateBestRoute(swapAmount);

      await tokenSwapper.executeSwap(swapAmount, res.path, 0, {
        value: swapAmount,
      });

      console.log(
        "20 ETH -> ",
        (Number(res.expectedUsdtAmount) / 1e6).toString(),
        "USDT, path: ",
        res.path.toString()
      );

      expect(await usdt.balanceOf(owner.address)).to.equal(
        balanceBefore.add(res.expectedUsdtAmount)
      );
    });
  });

  describe("should swap 20 ETH to USDT (uniswap v2, sushiswap, uniswap v3)", () => {
    before(async () => {
      await tokenSwapper.addUniswapV3Pool(USDC, WETH, { fee: 500 });
      await tokenSwapper.addUniswapV3Pool(DAI, USDC, { fee: 100 });
      await tokenSwapper.addUniswapV3Pool(USDC, WETH, { fee: 3000 });
      await tokenSwapper.addUniswapV3Pool(WETH, USDT, { fee: 3000 });
      await tokenSwapper.addUniswapV3Pool(DAI, USDC, { fee: 500 });
      await tokenSwapper.addUniswapV3Pool(USDC, USDT, { fee: 100 });
      await tokenSwapper.addUniswapV3Pool(WETH, USDT, { fee: 500 });
      await tokenSwapper.addUniswapV3Pool(WBTC, WETH, { fee: 3000 });
      await tokenSwapper.addUniswapV3Pool(WBTC, WETH, { fee: 500 });
      await tokenSwapper.addUniswapV3Pool(WBTC, USDC, { fee: 3000 });
    });

    it("20 ETH -> USDT: direct swap (uniswap v2, sushiswap, uniswap v3)", async () => {
      const balanceBefore = await usdt.balanceOf(owner.address);

      const res = await tokenSwapper.callStatic.calculateBestRoute(swapAmount);

      await tokenSwapper.swapETHToUSDT(swapAmount, 0, {
        value: swapAmount,
      });

      console.log(
        "20 ETH -> ",
        (Number(res.expectedUsdtAmount) / 1e6).toString(),
        "USDT, path: ",
        res.path.toString()
      );

      expect(await usdt.balanceOf(owner.address)).to.equal(
        balanceBefore.add(res.expectedUsdtAmount)
      );
    });

    it("20 ETH -> USDT: execute (uniswap v2, sushiswap, uniswap v3)", async () => {
      const balanceBefore = await usdt.balanceOf(owner.address);

      const res = await tokenSwapper.callStatic.calculateBestRoute(swapAmount);

      await tokenSwapper.executeSwap(swapAmount, res.path, 0, {
        value: swapAmount,
      });

      console.log(
        "20 ETH -> ",
        (Number(res.expectedUsdtAmount) / 1e6).toString(),
        "USDT, path: ",
        res.path.toString()
      );

      expect(await usdt.balanceOf(owner.address)).to.equal(
        balanceBefore.add(res.expectedUsdtAmount)
      );
    });
  });

  describe("should swap 20 ETH to USDT (uniswap v2, sushiswap, uniswap v3, curve)", () => {
    before(async () => {
      await tokenSwapper.addCurvePool(USDT, WETH, {
        minter: "0xf5f5b97624542d72a9e06f04804bf81baa15e2b4",
        isV2: true,
        i: 0,
        j: 2,
      });
      await tokenSwapper.addCurvePool(USDT, WBTC, {
        minter: "0xf5f5b97624542d72a9e06f04804bf81baa15e2b4",
        isV2: true,
        i: 0,
        j: 1,
      });
      await tokenSwapper.addCurvePool(WBTC, WETH, {
        minter: "0xf5f5b97624542d72a9e06f04804bf81baa15e2b4",
        isV2: true,
        i: 1,
        j: 2,
      });

      await tokenSwapper.addCurvePool(USDC, WETH, {
        minter: "0x7f86bf177dd4f3494b841a37e810a34dd56c829b",
        isV2: true,
        i: 0,
        j: 2,
      });
      await tokenSwapper.addCurvePool(USDC, WBTC, {
        minter: "0x7f86bf177dd4f3494b841a37e810a34dd56c829b",
        isV2: true,
        i: 0,
        j: 1,
      });
      await tokenSwapper.addCurvePool(WBTC, WETH, {
        minter: "0x7f86bf177dd4f3494b841a37e810a34dd56c829b",
        isV2: true,
        i: 1,
        j: 2,
      });

      await tokenSwapper.addCurvePool(DAI, USDC, {
        minter: "0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7",
        isV2: false,
        i: 0,
        j: 1,
      });
      await tokenSwapper.addCurvePool(DAI, USDT, {
        minter: "0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7",
        isV2: false,
        i: 0,
        j: 2,
      });
      await tokenSwapper.addCurvePool(USDC, USDT, {
        minter: "0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7",
        isV2: false,
        i: 1,
        j: 2,
      });
    });

    it("20 ETH -> USDT: direct swap (uniswap v2, sushiswap, uniswap v3, curve)", async () => {
      const balanceBefore = await usdt.balanceOf(owner.address);

      const res = await tokenSwapper.callStatic.calculateBestRoute(swapAmount);

      await tokenSwapper.swapETHToUSDT(swapAmount, 0, {
        value: swapAmount,
      });

      console.log(
        "20 ETH -> ",
        (Number(res.expectedUsdtAmount) / 1e6).toString(),
        "USDT, path: ",
        res.path.toString()
      );

      expect(await usdt.balanceOf(owner.address)).to.equal(
        balanceBefore.add(res.expectedUsdtAmount)
      );
    });

    it("20 ETH -> USDT: execute (uniswap v2, sushiswap, uniswap v3, curve)", async () => {
      const balanceBefore = await usdt.balanceOf(owner.address);

      const res = await tokenSwapper.callStatic.calculateBestRoute(swapAmount);

      await tokenSwapper.executeSwap(swapAmount, res.path, 0, {
        value: swapAmount,
      });

      console.log(
        "20 ETH -> ",
        (Number(res.expectedUsdtAmount) / 1e6).toString(),
        "USDT, path: ",
        res.path.toString()
      );

      expect(await usdt.balanceOf(owner.address)).to.equal(
        balanceBefore.add(res.expectedUsdtAmount)
      );
    });
  });
});
