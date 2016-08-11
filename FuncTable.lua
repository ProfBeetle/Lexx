    
    ------------------------------------------------------
    --
    --------------------------------- Functional table
    --
    -- I have no memory of where I got this, and I can't
	-- find it again. If it's yours let me know!
    --
    ------------------------------------------------------
    
    FuncTable = {}
    FuncTable.__index = FuncTable
    function FuncTable.new(values)
        local self = setmetatable({}, FuncTable)
        for key, value in pairs (values) do
            self[key] = value
        end
        return self
    end
    
    function FuncTable:each(onEach)
        for key, value in pairs (self) do
            onEach(key, value)
        end
    end
    
    function FuncTable:foldRight(init, onEach)
        local nextVal = init
        self:each(function(key, value)
            nextVal = onEach(nextVal, key, value)
        end)
        return nextVal
    end
    
    function FuncTable:map(onEach)
        local result = self:foldRight(FuncTable.new({}), function(newTable, key, value)
            newTable[#newTable+1] = onEach(key, value)
            return newTable
        end)
        return result
    end
    
    function FuncTable:filter(onEach)
        local result = self:foldRight(FuncTable.new({}), function(newTable, key, value)
            if (onEach(key, value) == 0) then
                newTable[key] = value
            end
            return newTable
        end)
        return result
    end

return FuncTable