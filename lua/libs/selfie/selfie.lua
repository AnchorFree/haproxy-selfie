local selfie = {}

-- Returns the difference between two points
-- in time. Args should be tables as returned by core.now() function.
selfie.difftime = function(t2,t1,as_string)

     local seconds = math.abs(t2.sec - t1.sec)
     local milliseconds = math.floor(math.abs( (t2.usec - t1.usec)/1000 ))
     if as_string then
         return seconds.."."..milliseconds
     end
     return seconds, milliseconds

end

return selfie
