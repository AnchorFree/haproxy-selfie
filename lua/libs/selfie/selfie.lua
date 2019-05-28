local selfie = {}

-- Returns the difference between two points
-- in time in seconds (with millisecond presicion). Args should be tables as returned by core.now() function.
selfie.difftime = function(t2, t1, as_string)

    if t2 and t2.sec and t2.usec and t1 and t1.sec and t1.usec then
       local seconds = t2.sec - t1.sec + (t2.usec - t1.usec) / 1000000
       local seconds_string = string.format("%.3f", seconds)
       if as_string then
            return seconds_string
       else
            return tonumber(seconds_string)
       end
    end
    return nil, "wrong format of arguments"

end

return selfie
