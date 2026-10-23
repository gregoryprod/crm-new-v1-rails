module Booking
  class Error < StandardError
    attr_reader :status, :code

    def initialize(status, code)
      @status = status
      @code = code
      super(code)
    end
  end
end
