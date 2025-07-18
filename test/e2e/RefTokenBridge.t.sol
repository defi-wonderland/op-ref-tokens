// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {E2EBase} from './E2EBase.sol';
import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {IRefTokenBridge} from 'contracts/RefTokenBridge.sol';
import {IRefToken} from 'interfaces/IRefToken.sol';
import {IUniSwapExecutor} from 'interfaces/external/IUniSwapExecutor.sol';
import {BASE_CHAIN_ID, OP_CHAIN_ID, UNI_CHAIN_ID} from 'src/utils/Constants.sol';

contract E2ERefTokenBridgeTest is E2EBase {
  /**
   * @notice Test send and execute in the op chain and relay and execute in the unichain chain
   * @dev This test will create a pool with the ref op token and usdc in the unichain chain,
   * send the op from the op chain, relay and execute in the unichain chain
   */
  function test_sendAndExecuteOpChainAndRelayAndExecuteUnichain() public {
    // Create the pool with the ref op token and usdc in the unichain chain
    _createPoolOpRefTokenAndUSDCInUnichain();

    // After the pool is created, send the op from the op chain and relay and execute in the unichain chain
    vm.selectFork(_optimismChainId);

    // Set up user funds
    vm.prank(_WHALE_IN_OPTIMISM_CHAIN);
    _OP_OPTIMISM.transfer(address(_user), _STANDARD_BRIDGE_AMOUNT);

    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_USDC_UNICHAIN));

    // Precalculate the ref op token metadata
    IRefToken.RefTokenMetadata memory _refOpTokenMetadataOptimism =
      _precalculateRefTokenMetadata(address(_OP_OPTIMISM), OP_CHAIN_ID);

    // Create the execution data
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_unichainUniSwapExecutor),
      destinationChainId: UNI_CHAIN_ID,
      refundAddress: _refund,
      data: abi.encode(_v4SwapParams)
    });

    // Send the op from op to unichain
    vm.startPrank(_user);
    _OP_OPTIMISM.approve(address(_opRefTokenBridge), _STANDARD_SWAP_AMOUNT);
    _opRefTokenBridge.sendAndExecute(
      OP_CHAIN_ID, UNI_CHAIN_ID, address(_OP_OPTIMISM), _STANDARD_SWAP_AMOUNT, _recipient, _executionData
    );
    vm.stopPrank();

    // Check that the op is on the bridge
    assertEq(_OP_OPTIMISM.balanceOf(address(_opRefTokenBridge)), _STANDARD_SWAP_AMOUNT + _OP_AMOUNT_TO_RELAY);
    // Check that the op is not on the user
    assertEq(_OP_OPTIMISM.balanceOf(_user), 0);

    // Check that the ref op is deployed
    address _refOpOptimism = _opRefTokenBridge.nativeToRefToken(address(_OP_OPTIMISM), OP_CHAIN_ID);
    assertEq(_refOpOptimism, _precalculateRefTokenAddress(address(_opRefTokenBridge), _refOpTokenMetadataOptimism));

    // Check that the ref op total supply is zero
    assertEq(IERC20(_refOpOptimism).totalSupply(), 0);

    // After the op is sent, relay and execute in the unichain chain
    vm.selectFork(_unichainChainId);

    // Relay the op to the unichain chain
    vm.startPrank(_RELAYER);
    relayAllMessages();

    vm.stopPrank();

    // Check that the ref op is deployed
    address _refOpUnichain = _unichainRefTokenBridge.nativeToRefToken(address(_OP_OPTIMISM), OP_CHAIN_ID);
    assertEq(
      _refOpUnichain, _precalculateRefTokenAddress(address(_unichainRefTokenBridge), _refOpTokenMetadataOptimism)
    );

    // Check that the ref op total supply is the amount of op sent
    assertEq(IERC20(_refOpUnichain).totalSupply(), _STANDARD_SWAP_AMOUNT + _OP_AMOUNT_TO_RELAY);

    // Check that the recipient received the usdc in unichain
    assertGt(IERC20(_USDC_UNICHAIN).balanceOf(_recipient), _v4SwapParams.amountOutMin);
  }

  /**
   * @notice Test send and execute in the op chain and relay and execute in the unichain chain and send to base chain
   * @dev This test will create a pool with the ref op token and usdc in the unichain chain, send the op from the op chain, relay and execute in the unichain chain
   */
  function test_sendAndExecuteOpChainAndRelayAndExecuteUnichainAndSendBaseChain() public {
    // Create the pool with the ref op token and usdc in the unichain chain
    _createPoolOpRefTokenAndUSDCInUnichain();

    // After the pool is created, send the op from the op chain and relay and execute in the unichain chain
    vm.selectFork(_optimismChainId);

    // Set up user funds
    vm.prank(_WHALE_IN_OPTIMISM_CHAIN);
    _OP_OPTIMISM.transfer(address(_user), _STANDARD_BRIDGE_AMOUNT);

    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_USDC_UNICHAIN));

    // Create the execution data
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_unichainUniSwapExecutor),
      destinationChainId: BASE_CHAIN_ID,
      refundAddress: _refund,
      data: abi.encode(_v4SwapParams)
    });

    // Precalculate the ref op token metadata
    IRefToken.RefTokenMetadata memory _refOpTokenMetadataOptimism =
      _precalculateRefTokenMetadata(address(_OP_OPTIMISM), OP_CHAIN_ID);

    // Send the op from op to unichain
    vm.startPrank(_user);
    _OP_OPTIMISM.approve(address(_opRefTokenBridge), _STANDARD_SWAP_AMOUNT);
    _opRefTokenBridge.sendAndExecute(
      OP_CHAIN_ID, UNI_CHAIN_ID, address(_OP_OPTIMISM), _STANDARD_SWAP_AMOUNT, _recipient, _executionData
    );
    vm.stopPrank();

    // Check that the op is on the bridge
    assertEq(_OP_OPTIMISM.balanceOf(address(_opRefTokenBridge)), _STANDARD_SWAP_AMOUNT + _OP_AMOUNT_TO_RELAY);
    // Check that the op is not on the user
    assertEq(_OP_OPTIMISM.balanceOf(_user), 0);

    // Check that the ref op is deployed
    address _refOpOptimism = _opRefTokenBridge.nativeToRefToken(address(_OP_OPTIMISM), OP_CHAIN_ID);
    assertEq(_refOpOptimism, _precalculateRefTokenAddress(address(_opRefTokenBridge), _refOpTokenMetadataOptimism));

    // Check that the ref op total supply is zero
    assertEq(IERC20(_refOpOptimism).totalSupply(), 0);

    // After the op is sent, relay and execute in the unichain chain
    vm.selectFork(_unichainChainId);

    // Relay the op to the unichain chain
    vm.startPrank(_RELAYER);
    relayAllMessages();
    vm.stopPrank();

    // Precalculate the ref USDC address on the base chain
    IRefToken.RefTokenMetadata memory _refUSDCMetadataUnichain =
      _precalculateRefTokenMetadata(address(_USDC_UNICHAIN), UNI_CHAIN_ID);
    address _refUSDCUnichain = _precalculateRefTokenAddress(address(_baseRefTokenBridge), _refUSDCMetadataUnichain);

    // Check that the ref op is deployed
    address _refOpUnichain = _unichainRefTokenBridge.nativeToRefToken(address(_OP_OPTIMISM), OP_CHAIN_ID);
    assertEq(
      _refOpUnichain, _precalculateRefTokenAddress(address(_unichainRefTokenBridge), _refOpTokenMetadataOptimism)
    );

    // Check that the ref op total supply is the amount of op sent
    assertEq(IERC20(_refOpUnichain).totalSupply(), _OP_AMOUNT_TO_RELAY + _STANDARD_SWAP_AMOUNT);

    // Check that the ref USDC is deployed
    assertEq(_refUSDCUnichain, _precalculateRefTokenAddress(address(_baseRefTokenBridge), _refUSDCMetadataUnichain));

    // Check that the ref USDC total supply is zero
    assertEq(IERC20(_refUSDCUnichain).totalSupply(), 0);

    // Relay the usdc to the base chain, the ref USDC will be deployed on the base chain
    vm.selectFork(_baseChainId);
    vm.startPrank(_RELAYER);

    relayAllMessages();

    vm.stopPrank();

    // Check that the ref usdc is deployed on the base chain
    address _refUSDCBase = _baseRefTokenBridge.nativeToRefToken(address(_USDC_UNICHAIN), UNI_CHAIN_ID);
    assertEq(_refUSDCBase, _precalculateRefTokenAddress(address(_baseRefTokenBridge), _refUSDCMetadataUnichain));

    // Check that the recipient received the ref usdc
    assertEq(IERC20(_refUSDCBase).balanceOf(_recipient), IERC20(_refUSDCUnichain).totalSupply());
  }

  /**
   * @notice Test send and execute in the op chain and relay and execute in the unichain chain and revert and relay back to the op chain
   * @dev This test will create a pool with the ref op token and usdc in the unichain chain, send the op from the op chain, relay and execute in the unichain chain
   */
  function test_sendAndExecuteOpChainAndRelayAndExecuteRevertAndRelayBackToOpChain() public {
    // After the pool is created, send the op from the op chain and relay and execute in the unichain chain
    vm.selectFork(_optimismChainId);

    // Set up user funds
    vm.prank(_WHALE_IN_OPTIMISM_CHAIN);
    _OP_OPTIMISM.transfer(address(_user), _STANDARD_BRIDGE_AMOUNT);

    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_USDC_UNICHAIN));

    // Create the execution data
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_unichainUniSwapExecutor),
      destinationChainId: UNI_CHAIN_ID,
      refundAddress: _refund,
      data: abi.encode(_v4SwapParams)
    });

    // Precalculate the ref op token metadata
    IRefToken.RefTokenMetadata memory _refOpTokenMetadataOptimism =
      _precalculateRefTokenMetadata(address(_OP_OPTIMISM), OP_CHAIN_ID);

    // Send the op from op to unichain
    vm.startPrank(_user);
    _OP_OPTIMISM.approve(address(_opRefTokenBridge), _STANDARD_SWAP_AMOUNT);
    _opRefTokenBridge.sendAndExecute(
      OP_CHAIN_ID, UNI_CHAIN_ID, address(_OP_OPTIMISM), _STANDARD_SWAP_AMOUNT, _recipient, _executionData
    );
    vm.stopPrank();

    // Check that the op is on the bridge
    assertEq(_OP_OPTIMISM.balanceOf(address(_opRefTokenBridge)), _STANDARD_SWAP_AMOUNT);
    // Check that the op is not on the user
    assertEq(_OP_OPTIMISM.balanceOf(_user), 0);

    // Check that the ref op is deployed
    address _refOpOptimism = _opRefTokenBridge.nativeToRefToken(address(_OP_OPTIMISM), OP_CHAIN_ID);
    assertEq(_refOpOptimism, _precalculateRefTokenAddress(address(_opRefTokenBridge), _refOpTokenMetadataOptimism));

    // Check that the ref op total supply is zero (not ref tokens should be minted on the native asset chain)
    assertEq(IERC20(_refOpOptimism).totalSupply(), 0);

    // Relay the op to the unichain chain to execute the swap
    vm.startPrank(_RELAYER);
    relayAllMessages();
    vm.stopPrank();

    // After the op is sent, relay and execute in the unichain chain
    vm.selectFork(_unichainChainId);

    // As the swap reverts, the op will be returned to the op chain
    vm.startPrank(_RELAYER);
    relayMessages(vm.getRecordedLogs(), OP_CHAIN_ID);
    vm.stopPrank();

    // Check that the ref op is deployed
    address _refOpUnichain = _unichainRefTokenBridge.nativeToRefToken(address(_OP_OPTIMISM), OP_CHAIN_ID);
    assertEq(
      _refOpUnichain, _precalculateRefTokenAddress(address(_unichainRefTokenBridge), _refOpTokenMetadataOptimism)
    );

    // Check that the ref op total supply is zero, as the swap reverted
    assertEq(IERC20(_refOpUnichain).totalSupply(), 0);

    vm.selectFork(_optimismChainId);

    // Check that the refund is sent to the refund address
    assertEq(IERC20(_OP_OPTIMISM).balanceOf(_refund), _STANDARD_SWAP_AMOUNT);
    // Check that the bridge is not holding any op amount
    assertEq(_OP_OPTIMISM.balanceOf(address(_opRefTokenBridge)), 0);
    // Check that the op is not on the user
    assertEq(_OP_OPTIMISM.balanceOf(_user), 0);
  }

  /**
   * @notice Test swap op to usdc in the op chain and send to the unichain chain
   */
  function test_swapOpToUsdcInOpChainAndSendToUnichain() public {
    // Swap OP from USDC, and then send the OP from the op chain and relay and execute in the unichain chain
    vm.selectFork(_optimismChainId);

    // Set up user funds
    vm.prank(_WHALE_IN_OPTIMISM_CHAIN);
    _OP_OPTIMISM.transfer(address(_user), _STANDARD_BRIDGE_AMOUNT);

    // Create the v4 swap params
    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_USDC_OPTIMISM));

    // Empty execution data
    IRefTokenBridge.ExecutionData memory _executionData;

    // Swap op to usdc in the op chain and send to the unichain chain
    vm.startPrank(_user);
    _OP_OPTIMISM.approve(address(_opUniSwapExecutor), _STANDARD_SWAP_AMOUNT);
    _opUniSwapExecutor.swapAndSend(
      address(_OP_OPTIMISM),
      uint128(_STANDARD_SWAP_AMOUNT),
      abi.encode(_v4SwapParams),
      UNI_CHAIN_ID,
      _recipient,
      _executionData
    );
    vm.stopPrank();

    // Precalculate the ref USDC address on the unichain chain
    IRefToken.RefTokenMetadata memory _refUsdcOptimismMetadata =
      _precalculateRefTokenMetadata(address(_USDC_OPTIMISM), OP_CHAIN_ID);

    // Check that the ref USDC is deployed
    address _refUsdcOptimism = _opRefTokenBridge.nativeToRefToken(address(_USDC_OPTIMISM), OP_CHAIN_ID);
    assertEq(_refUsdcOptimism, _precalculateRefTokenAddress(address(_opRefTokenBridge), _refUsdcOptimismMetadata));

    // Check that the ref USDC total supply is zero
    assertEq(IERC20(_refUsdcOptimism).totalSupply(), 0);

    // After the USDC is sent, relay and execute in the unichain
    vm.selectFork(_unichainChainId);

    // Relay all messages
    vm.startPrank(_RELAYER);
    relayAllMessages();
    vm.stopPrank();

    // Check that the ref USDC is deployed
    address _refUsdcUnichain = _unichainRefTokenBridge.nativeToRefToken(address(_USDC_OPTIMISM), OP_CHAIN_ID);
    assertEq(_refUsdcUnichain, _precalculateRefTokenAddress(address(_unichainRefTokenBridge), _refUsdcOptimismMetadata));

    // Check that the usdc is received in the unichain chain
    assertEq(IERC20(_refUsdcUnichain).balanceOf(_recipient), IERC20(_refUsdcUnichain).totalSupply());
  }

  /**
   * @notice Test swap usdc to op in the op chain and send and execute to swap in the unichain chain
   * @dev This test will create a pool with the ref op token and usdc in the unichain chain, swap usdc to op in the op chain,
   * send and execute to swap in the unichain chain and check that the ref token is deployed and the pool is created
   */
  function test_swapUsdcToOpInOpChainAndSendAndExecuteToUnichain() public {
    // Create the pool with the ref op token and usdc in the unichain chain
    _createPoolOpRefTokenAndUSDCInUnichain();

    // After the pool is created, swap usdc to op in the op chain and send and execute to swap in the unichain chain
    vm.selectFork(_optimismChainId);

    // Set up user funds
    // The amount of usdc to swap is 1000 USDC
    uint256 _usdcAmount = 1000 * 10 ** 6;
    vm.prank(_WHALE_IN_OPTIMISM_CHAIN);
    _USDC_OPTIMISM.transfer(address(_user), _usdcAmount);

    // Create the v4 swap params for the first swap
    IUniSwapExecutor.V4SwapExactInParams memory _v4FirstSwapParams = _createV4SwapParams(address(_OP_OPTIMISM));

    // Create the v4 swap params for the second swap
    IUniSwapExecutor.V4SwapExactInParams memory _v4SecondSwapParams = _createV4SwapParams(address(_USDC_UNICHAIN));

    // Execution data for the second swap in the unichain chain
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_unichainUniSwapExecutor),
      destinationChainId: UNI_CHAIN_ID,
      refundAddress: _refund,
      data: abi.encode(_v4SecondSwapParams)
    });

    // Swap usdc to op in the op chain and send and execute to swap in the unichain chain
    vm.startPrank(_user);
    _USDC_OPTIMISM.approve(address(_opUniSwapExecutor), _usdcAmount);
    _opUniSwapExecutor.swapAndSend(
      address(_USDC_OPTIMISM),
      uint128(_usdcAmount),
      abi.encode(_v4FirstSwapParams),
      UNI_CHAIN_ID,
      _recipient,
      _executionData
    );
    vm.stopPrank();

    // Precalculate the ref op token metadata
    IRefToken.RefTokenMetadata memory _refOpTokenMetadataOptimism =
      _precalculateRefTokenMetadata(address(_OP_OPTIMISM), OP_CHAIN_ID);

    address _refOpOptimism = _opRefTokenBridge.nativeToRefToken(address(_OP_OPTIMISM), OP_CHAIN_ID);

    // Check that the ref op is deployed
    assertEq(_refOpOptimism, _precalculateRefTokenAddress(address(_opRefTokenBridge), _refOpTokenMetadataOptimism));

    // Check that the ref op total supply is zero
    assertEq(IERC20(_refOpOptimism).totalSupply(), 0);

    // After the op is sent, relay and execute in the unichain chain
    vm.selectFork(_unichainChainId);

    // Relay all messages
    vm.startPrank(_RELAYER);
    relayAllMessages();
    vm.stopPrank();

    // Check that the ref USDC is deployed
    address _refOpUnichain = _unichainRefTokenBridge.nativeToRefToken(address(_OP_OPTIMISM), OP_CHAIN_ID);
    assertEq(
      _refOpUnichain, _precalculateRefTokenAddress(address(_unichainRefTokenBridge), _refOpTokenMetadataOptimism)
    );

    // Check that the op bridge was swapped to usdc in the unichain chain
    assertEq(IERC20(_refOpUnichain).balanceOf(_recipient), 0);
    // Check that the usdc is received in the unichain chain
    assertGt(IERC20(_USDC_UNICHAIN).balanceOf(_recipient), 0);
  }

  /**
   * @notice Test swap usdc to op in the op chain and send and swap ref op to usdc in the unichain chain and send to base chain
   * @dev This test will create a pool with the ref op token and usdc in the unichain chain, swap usdc to op in the op chain,
   * send and execute to swap in the unichain chain, swap ref op to usdc in the unichain chain and send to base chain
   * and check that the ref token is deployed and the pool is created
   */
  function test_swapUsdcToOpInOpChainAndSendAndSwapRefOpToUsdcInUnichainAndSendToBaseChain() public {
    // Create the pool with the ref op token and usdc in the unichain chain
    _createPoolOpRefTokenAndUSDCInUnichain();

    // After the pool is created, swap usdc to op in the op chain and send and execute to swap in the unichain chain
    vm.selectFork(_optimismChainId);

    // Set up user funds
    // The amount of usdc to swap is 1000 USDC
    uint256 _usdcAmount = 1000 * 10 ** 6;
    vm.prank(_WHALE_IN_OPTIMISM_CHAIN);
    _USDC_OPTIMISM.transfer(address(_user), _usdcAmount);

    // Create the v4 swap params for the first swap
    IUniSwapExecutor.V4SwapExactInParams memory _v4FirstSwapParams = _createV4SwapParams(address(_OP_OPTIMISM));

    // Create the v4 swap params for the second swap
    IUniSwapExecutor.V4SwapExactInParams memory _v4SecondSwapParams = _createV4SwapParams(address(_USDC_UNICHAIN));

    // Execution data for the second swap in the unichain chain
    IRefTokenBridge.ExecutionData memory _executionData;

    // Swap usdc to op in the op chain and send and execute to swap in the unichain chain
    vm.startPrank(_user);
    _USDC_OPTIMISM.approve(address(_opUniSwapExecutor), _usdcAmount);
    _opUniSwapExecutor.swapAndSend(
      address(_USDC_OPTIMISM),
      uint128(_usdcAmount),
      abi.encode(_v4FirstSwapParams),
      UNI_CHAIN_ID,
      _recipient,
      _executionData
    );
    vm.stopPrank();

    // Precalculate the ref op token metadata
    IRefToken.RefTokenMetadata memory _refOpTokenMetadataOptimism =
      _precalculateRefTokenMetadata(address(_OP_OPTIMISM), OP_CHAIN_ID);

    address _refOpOptimism = _opRefTokenBridge.nativeToRefToken(address(_OP_OPTIMISM), OP_CHAIN_ID);
    // Check that the ref op is deployed
    assertEq(_refOpOptimism, _precalculateRefTokenAddress(address(_opRefTokenBridge), _refOpTokenMetadataOptimism));
    // Check that the ref op total supply is zero
    assertEq(IERC20(_refOpOptimism).totalSupply(), 0);

    vm.selectFork(_unichainChainId);

    // Relay all messages
    vm.startPrank(_RELAYER);
    relayAllMessages();
    vm.stopPrank();

    // Check that the ref op is deployed
    address _refOpUnichain = _unichainRefTokenBridge.nativeToRefToken(address(_OP_OPTIMISM), OP_CHAIN_ID);
    assertEq(
      _refOpUnichain, _precalculateRefTokenAddress(address(_unichainRefTokenBridge), _refOpTokenMetadataOptimism)
    );

    uint256 _refOpBalance = IERC20(_refOpUnichain).balanceOf(_recipient);

    // Check that the recipient received the ref op
    assertGt(_refOpBalance, 0);

    address _baseRecipient = makeAddr('baseRecipient');

    // Swap ref op to usdc in the unichain chain and send to the base chain
    vm.startPrank(_recipient);
    IERC20(_refOpUnichain).approve(address(_unichainUniSwapExecutor), _refOpBalance);
    _unichainUniSwapExecutor.swapAndSend(
      address(_refOpUnichain),
      uint128(_refOpBalance),
      abi.encode(_v4SecondSwapParams),
      BASE_CHAIN_ID,
      _baseRecipient,
      _executionData
    );
    vm.stopPrank();

    // Precalculate the ref op token metadata
    IRefToken.RefTokenMetadata memory _refUsdcMetadataBase =
      _precalculateRefTokenMetadata(address(_USDC_UNICHAIN), UNI_CHAIN_ID);

    vm.selectFork(_baseChainId);

    // Relay all messages
    vm.startPrank(_RELAYER);
    relayAllMessages();
    vm.stopPrank();

    // Check that the ref USDC is deployed
    address _refUsdcBase = _baseRefTokenBridge.nativeToRefToken(address(_USDC_UNICHAIN), UNI_CHAIN_ID);
    assertEq(_refUsdcBase, _precalculateRefTokenAddress(address(_baseRefTokenBridge), _refUsdcMetadataBase));

    // Check that the usdc is received in the base chain
    assertEq(IERC20(_refUsdcBase).balanceOf(_baseRecipient), IERC20(_refUsdcBase).totalSupply());
  }

  /**
   * @notice Test different users send in the op chain and execute in the unichain chain
   * @dev This test will create a pool with the ref op token and usdc in the unichain chain,
   * send the op from the op chain and relay and execute in the unichain chain
   * and check that the ref token is deployed and the pool is created
   */
  function test_differentUsersSendInOpAndExecuteInUnichain() public {
    // Create the pool with the ref op token and usdc in the unichain chain
    _createPoolOpRefTokenAndUSDCInUnichain();

    vm.selectFork(_optimismChainId);

    // Set up another user and recipient
    address _anotherUser = makeAddr('anotherUser');
    address _anotherRecipient = makeAddr('anotherRecipient');

    // The amount of op to swap for the second user
    uint256 _secondUserSwapAmount = _STANDARD_BRIDGE_AMOUNT * 2;

    // Set up user funds
    vm.startPrank(_WHALE_IN_OPTIMISM_CHAIN);
    _OP_OPTIMISM.transfer(address(_user), _STANDARD_BRIDGE_AMOUNT);
    _OP_OPTIMISM.transfer(address(_anotherUser), _secondUserSwapAmount);
    vm.stopPrank();

    // Create the v4 swap params
    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_USDC_UNICHAIN));

    // Execution data for the swap in the unichain chain
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_unichainUniSwapExecutor),
      destinationChainId: UNI_CHAIN_ID,
      refundAddress: _refund,
      data: abi.encode(_v4SwapParams)
    });

    // Send the op from the op chain and relay and execute in the unichain chain
    vm.startPrank(_user);
    _OP_OPTIMISM.approve(address(_opRefTokenBridge), _STANDARD_BRIDGE_AMOUNT);
    _opRefTokenBridge.sendAndExecute(
      OP_CHAIN_ID, UNI_CHAIN_ID, address(_OP_OPTIMISM), _STANDARD_BRIDGE_AMOUNT, _recipient, _executionData
    );
    vm.stopPrank();

    // Precalculate the ref op token metadata
    IRefToken.RefTokenMetadata memory _refOpTokenMetadata =
      _precalculateRefTokenMetadata(address(_OP_OPTIMISM), OP_CHAIN_ID);

    // Check that the op is deployed
    address _refOpOptimism = _opRefTokenBridge.nativeToRefToken(address(_OP_OPTIMISM), OP_CHAIN_ID);
    assertEq(_refOpOptimism, _precalculateRefTokenAddress(address(_opRefTokenBridge), _refOpTokenMetadata));

    // Check that the op total supply is zero
    assertEq(IERC20(_refOpOptimism).totalSupply(), 0);

    // Check that the op is on the user
    assertEq(IERC20(_OP_OPTIMISM).balanceOf(_user), 0);
    assertEq(IERC20(_OP_OPTIMISM).balanceOf(address(_opRefTokenBridge)), _STANDARD_BRIDGE_AMOUNT + _OP_AMOUNT_TO_RELAY);

    // Send the op from the op chain and relay and execute in the unichain chain
    vm.startPrank(_anotherUser);
    _OP_OPTIMISM.approve(address(_opRefTokenBridge), _secondUserSwapAmount);
    _opRefTokenBridge.sendAndExecute(
      OP_CHAIN_ID, UNI_CHAIN_ID, address(_OP_OPTIMISM), _secondUserSwapAmount, _anotherRecipient, _executionData
    );
    vm.stopPrank();

    // Check that the op total supply is zero
    assertEq(IERC20(_refOpOptimism).totalSupply(), 0);

    // Check that the op is on the user
    assertEq(IERC20(_OP_OPTIMISM).balanceOf(_user), 0);
    assertEq(IERC20(_OP_OPTIMISM).balanceOf(_anotherUser), 0);
    assertEq(
      IERC20(_OP_OPTIMISM).balanceOf(address(_opRefTokenBridge)),
      _STANDARD_BRIDGE_AMOUNT + _secondUserSwapAmount + _OP_AMOUNT_TO_RELAY
    );

    vm.selectFork(_unichainChainId);

    // Relay all messages
    vm.startPrank(_RELAYER);
    relayAllMessages();
    vm.stopPrank();

    // Check that the op is deployed
    address _refOpUnichain = _unichainRefTokenBridge.nativeToRefToken(address(_OP_OPTIMISM), OP_CHAIN_ID);
    assertEq(_refOpUnichain, _precalculateRefTokenAddress(address(_unichainRefTokenBridge), _refOpTokenMetadata));

    // Check that the op total supply is zero
    assertEq(
      IERC20(_refOpUnichain).totalSupply(), _STANDARD_BRIDGE_AMOUNT + _secondUserSwapAmount + _OP_AMOUNT_TO_RELAY
    );

    // Check that the usdc is received in the unichain chain
    assertGt(_USDC_UNICHAIN.balanceOf(_recipient), 0);
    assertGt(_USDC_UNICHAIN.balanceOf(_anotherRecipient), 0);
  }

  /**
   * @notice Helper function to create the pool with the ref op token and usdc in the unichain chain
   */
  function _createPoolOpRefTokenAndUSDCInUnichain() internal {
    // Send and execute in the op chain
    vm.selectFork(_optimismChainId);

    // Set up user funds
    vm.prank(_WHALE_IN_OPTIMISM_CHAIN);
    _OP_OPTIMISM.transfer(address(_user), _OP_AMOUNT_TO_RELAY);

    IRefToken.RefTokenMetadata memory _refOpTokenMetadata =
      _precalculateRefTokenMetadata(address(_OP_OPTIMISM), OP_CHAIN_ID);

    // Send the op from op to unichain
    vm.startPrank(_user);
    _OP_OPTIMISM.approve(address(_opRefTokenBridge), _OP_AMOUNT_TO_RELAY);
    _opRefTokenBridge.send(OP_CHAIN_ID, UNI_CHAIN_ID, address(_OP_OPTIMISM), _OP_AMOUNT_TO_RELAY, _poolDeployer);
    vm.stopPrank();

    vm.selectFork(_unichainChainId);

    // Set up user funds
    vm.prank(_WHALE_IN_UNICHAIN_CHAIN);
    _USDC_UNICHAIN.transfer(address(_poolDeployer), _USDC_AMOUNT_TO_RELAY);

    // Relay the op to the unichain chain
    vm.startPrank(_RELAYER);
    relayAllMessages();
    vm.stopPrank();

    // Check that the ref token is deployed
    address _refOpUnichain = _precalculateRefTokenAddress(address(_unichainRefTokenBridge), _refOpTokenMetadata);

    // Check balances of the pool deployer
    assertEq(IERC20(_refOpUnichain).balanceOf(_poolDeployer), _OP_AMOUNT_TO_RELAY);
    assertEq(_USDC_UNICHAIN.balanceOf(_poolDeployer), _USDC_AMOUNT_TO_RELAY);

    vm.startPrank(_poolDeployer);
    // Fixed value for the sqrt price usdc 1 OP ~= 0.5 USDC
    uint160 _sqrtPriceX96 = 56_022_770_974_786_135_785_472; // = sqrt(0.5 USDC/OP) * 2**96
    // Fixed value for the tick lower and upper
    int24 _tickLower = 283_260; // 60 * 4721, below current price
    int24 _tickUpper = 283_320; // 60 * 4722, above current price
    uint128 _liquidity = 10 ether;

    _createPoolAndMintPosition(
      _UNICHAIN_POSITION_MANAGER,
      _unichainUniSwapExecutor,
      _recipient,
      address(_refOpUnichain),
      address(_USDC_UNICHAIN),
      _OP_AMOUNT_TO_RELAY,
      _USDC_AMOUNT_TO_RELAY,
      _sqrtPriceX96,
      _tickLower,
      _tickUpper,
      _liquidity
    );
    vm.stopPrank();
  }
}
