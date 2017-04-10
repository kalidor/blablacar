# Author: Gregory 'kalidor' Charbonneau
# Email: kalidor -AT- unixed -DOT- fr
# Published under the terms of the wtfPLv2

#Error class during a trip validation
class ValidateTripError < StandardError
end

#Error class during the authentication
class AuthenticationError < StandardError
end

#Error class while sending a message back to a question
class SendReponseMessageError < StandardError
end

#Error class during an acceptation of a passenger
class AcceptationError < StandardError
end

#Error class during seat update for a trip
class UpdateSeatError < StandardError
end

#Error class during a trip duplication
class DuplicateTripError < StandardError
end

#Error class during the check of a duplication
class CheckPublishedTripError < StandardError
end

#Error class during Virement class parsing
class VirementError < StandardError
end
