// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract Web3RSVP {
    struct CreateEvent {
        bytes32 eventId;
        string eventDataCID;
        address eventOwner;
        uint256 eventTimestamp;
        uint256 deposit;
        uint256 maxCapacity;
        address[] confirmedRSVPs;
        address[] claimedRSVPs;
        bool paidOut;
    }

    event NewEventCreated(
        bytes32 eventId,
        address creatorAddress,
        uint256 eventTimestamp,
        uint256 maxCapacity,
        uint256 deposit,
        string eventDataCID
    );

    event NewEventAttendeeRSVPed(bytes32 eventId, address attendeeAddress);

    event AttendeeConfirmed(bytes32 eventId, address attendeeAddress);

    event DepositsPaidOut(bytes32 eventId);

    mapping(bytes32 => CreateEvent) public idToEvent;

    function createNewEvent(
        uint256 eventTimestamp,
        uint256 deposit,
        uint256 maxCapacity,
        string calldata eventDataCID
    ) external {
        // generate an event ID based on other things passed in
        bytes32 eventId = keccak256(
            abi.encodePacked(
                msg.sender,
                address(this),
                eventTimestamp,
                deposit,
                maxCapacity
            )
        );

        require(idToEvent[eventId].eventTimestamp == 0, "ALREADY REGISTERED");

        address[] memory confirmedRSVPs;
        address[] memory claimedRSVPs;

        // this creates a new CreateEvent struct and adds it to the idToEvent mapping
        idToEvent[eventId] = CreateEvent(
            eventId,
            eventDataCID,
            msg.sender,
            eventTimestamp,
            deposit,
            maxCapacity,
            confirmedRSVPs,
            claimedRSVPs,
            false
        );

        emit NewEventCreated(
            eventId,
            msg.sender,
            eventTimestamp,
            maxCapacity,
            deposit,
            eventDataCID
        );
    }

    function createNewRSVP(bytes32 eventId) external payable {
        // look up event from our mapping
        CreateEvent storage myEvent = idToEvent[eventId];

        // transfer deposit to our contract / require that they send enough ETH to cover the deposit requirement of this specific event
        require(
            msg.value == myEvent.deposit,
            "NOT ENOUGH!, You need to spend more ETH"
        );

        // require that the event hasn't already happened (<eventTimestamp)
        require(
            block.timestamp <= myEvent.eventTimestamp,
            "Event has already happened"
        );

        // make sure event is under max capacity
        require(
            myEvent.confirmedRSVPs.length < myEvent.maxCapacity,
            "This event has reached its capacity"
        );

        // require that msg.sender hasn't already registered for event
        for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
            require(
                myEvent.confirmedRSVPs[i] != msg.sender,
                "You are already registered for this event"
            );
        }

        // create new RSVP (reservation for event)
        myEvent.confirmedRSVPs.push(payable(msg.sender));

        emit NewEventAttendeeRSVPed(eventId, msg.sender);
    }

    // alias of confirmedAttendee
    function confirmAttendee(bytes32 eventId, address attendee) public {
        // look up event from our struct using the eventId
        CreateEvent storage myEvent = idToEvent[eventId];

        // require that msg.sender is the owner of the event - only the host should be able to check people in
        require(msg.sender == myEvent.eventOwner, "Not Authorized");

        // require that attendee trying to check in actually RSVP'd
        address rsvpConfirm;

        for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
            if (myEvent.confirmedRSVPs[i] == attendee) {
                rsvpConfirm = myEvent.confirmedRSVPs[i];
            }
        }

        require(rsvpConfirm == attendee, "No RSVP to confirm");

        // require that attendee is not already in the claimedRSVPs list AKA make sure they haven't already checked in
        for (uint8 i = 0; i < myEvent.claimedRSVPs.length; i++) {
            require(
                myEvent.claimedRSVPs[i] != attendee,
                "Already confirmed and claimed RSVP"
            );
        }

        // require that deposits are not already claimed by the event owner
        require(myEvent.paidOut == false, "Already paid out");

        // add the attendee to the claimedRSVPs list
        myEvent.claimedRSVPs.push(attendee);

        // sending eth back to the staker `https://solidity-by-example.org/sending-ether`
        (bool sent, ) = attendee.call{value: myEvent.deposit}("");

        // if this fails, remove the user from the array of claimed RSVPs
        if (!sent) {
            myEvent.claimedRSVPs.pop();
        }

        require(sent, "Failed to send Ether");

        emit AttendeeConfirmed(eventId, attendee);
    }

    function confirmAllAttendees(bytes32 eventId) external {
        // look up event from our struct with the eventId
        CreateEvent memory myEvent = idToEvent[eventId];

        // make sure you require that msg.sender is the owner of the event
        require(
            msg.sender == myEvent.eventOwner,
            "Not Authorized. Only owner can perform this operation"
        );

        // confirm each attendee in the rsvp array
        for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
            confirmAttendee(eventId, myEvent.confirmedRSVPs[i]);
        }
    }

    function withdrawUnclaimedDeposits(bytes32 eventId) external {
        // look up event
        CreateEvent memory myEvent = idToEvent[eventId];

        // check that the paidOut boolean still equals false AKA the money hasn't already been paid out
        require(!myEvent.paidOut, "Already paid");

        // check if it's been 7 days past myEvent.eventTimestamp
        require(
            block.timestamp >= (myEvent.eventTimestamp + 7 days),
            "Too early, wait for 1 week from when event RSVP"
        );

        // only the event owner can withdraw
        require(msg.sender == myEvent.eventOwner, "Must be event owner");

        // calculate how many peopl didn't claim by comparing
        uint256 unclaimed = myEvent.confirmedRSVPs.length -
            myEvent.claimedRSVPs.length;

        uint256 payout = unclaimed * myEvent.deposit;

        // mark as paid before sending to avoid reentrancy attack
        myEvent.paidOut = true;

        // send the payout to the owner
        (bool sent, ) = msg.sender.call{value: payout}("");

        // if this fails
        if (!sent) {
            myEvent.paidOut = false;
        }

        require(sent, "Failed to send Ether");

        emit DepositsPaidOut(eventId);
    }
}
