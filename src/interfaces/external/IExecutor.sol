// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IExecutor {
  function execute(bytes calldata _data) external;
}
