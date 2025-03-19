// SPDX-License-Identifier: MIT
// An example of a consumer contract that relies on a subscription for funding.
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract Consumer is VRFConsumerBaseV2Plus {
    uint256 immutable s_subscriptionId;
    bytes32 immutable s_keyHash;
    uint256[] public s_randomWords;
    uint256 public s_requestId;

    event ReturnedRandomness(uint256[] randomWords);

    /**
     * @param subscriptionId - the subscription ID that this contract uses for funding requests
     * @param vrfCoordinator - coordinator, check https://docs.chain.link/vrf/v2-5/supported-networks
     * @param keyHash - the gas lane to use, which specifies the maximum gas price to bump to, check https://docs.chain.link/docs/vrf-contracts/#configurations
     */
    constructor(
        uint256 subscriptionId,
        address vrfCoordinator,
        bytes32 keyHash
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        s_keyHash = keyHash;
        s_subscriptionId = subscriptionId;
    }


    function requestRandomWords() external onlyOwner {
        s_requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_keyHash,
                subId: s_subscriptionId,
                requestConfirmations: 3,
                callbackGasLimit: 100000,
                numWords: 2,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
    }

    /**
     * @param  - id of the request
     * @param randomWords - array of random results from VRF Coordinator
     */
    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] calldata randomWords
    ) internal override {
        s_randomWords = randomWords;
        emit ReturnedRandomness(randomWords);
    }
}
