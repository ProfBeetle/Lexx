local FuncTable = require(game.ReplicatedStorage["FuncTable"])

--[[

--------------------------------- Lexx

A greedy lexical tokenizer

 - Jeff "ProfBeetle" Thomas - 2016/8/10
	
Lexx takes a string and breaks it into tokens. It's greedy in the sense that it will return
the longest match it finds, but it also returns other matches and failed matches to aid in
debugging (or if you don't want the longest match).

To do so it walks through a text string sending characters to Matchers, when all of the Matchers
have stopped matching it returns the longest successful match.

Using Lexx is simple, you create a new one and pass in the text to tokenize and an array of 
Matchers you wish to use to tokenize it.

	local lexx = Lexx.new("This is a test", {IdentifierMatcher.new(), WhitespaceMatcher.new()})

You can then call lexx.getNext() to get a token, the match will be in the results longestMatch field
if it found one. longestMatch will be nil if Lexx did not find a match. longestMatch
has this format
{
	token = <a 'tokens' value>,
	value = <the text of the token>
}

	lexx = lexx:getNext()
	
	print(lexx.longestMatch.token)
	print(lexx.longestMatch.value)

this will print

	identifier
	This

Lexx returns a copy of itself with it's values updated when you call getNext(),
so you use the returned value to call getNext on to get the next token. This is
why I assigned the returned value to 'lexx'.

	lexx = lexx:getNext() 
	print(lexx.longestMatch.token)
	print(lexx.longestMatch.value)

will print

	whitespace
	[blank space]
	
doing it again 

	lexx = lexx:getNext() 
	print(lexx.longestMatch.token)
	print(lexx.longestMatch.value)

will print

	identifier
	is

and so on.

Lexx keeps previous copies of itself in a 'previous' value, you can "wind back" to
any previous token by navigating down the 'previous' chain. for example

	print(lexx.previous.previous.longestMatch.value)
	
will result in

	This
	
Lexx also keeps 'next' values, so

	print(lexx.previous.next.longestMatch.value)
	
will result in

	is
	
You can start tokenizing again from a previous version of LEXX

	print(lexx.previous:getNext().longestMatch.value)
	
will also result in 

	is
	
HOWEVER Lexx also knows it has already tokenized if it has a 'next' value, so it wont 
acutally re-tokenize the string and just returns the 'next' value. If you want to force
re-tokenization (say you changed the string) you need to clear the 'next' value by
assigning it zero ('0'). DO NOT assign it 'nil', because of Lua's inheritance mechanism
this will cause Lexx to return the 'next' value of it's parent rather than re-tokenizing.

	lexx = lexx.previous
	lexx.next = 0
	lexx = lexx:getNext() -- this forced a re-tokenizing. 
	print(lexx.longestMatch.value)
	
results in

  is

For more examples take a look at the tests at the bottom of this file.
--]]
------------------------------------------------------

local tokens = {
    IDENTIFIER = "identifier",
    WHITESPACE = "whitespace",
    PUNCTUATION = "punctuation",
    KEYWORD = "keyword",
    INTEGER = "integer",
    FLOAT = "float",
    OPERATOR = "operator",
}


--------------------------------- 
--
-- Matchers
--
---------------------------------

--[[

Matchers are fed characters one at a time using the curried function returned by 
the getNextStep() function, for each character they are given they must 
decide one of 3 things

1. They need to keep going to make a match, in which case they put their next
curried step function into the result.matching array

2. They've found a match meeting their criteria and can stop matching. In
this case they put a data block in the result.success array. The data block
has this format:
{
	value = <text of the token>, 
	index = <the index of the END of the token>, 
	token = <a "tokens" value>
}

3. They've failed to find a match and need to stop matching. When this happens
the matcher should put a data block in the result.failures array with
information on why matching failed to help with debugging. What format this
information is in isn't really defined since Lexx never looks at it, it's for
debugging by the matcher programmer.

--]]

-- Matches common identifier patterns such as "i", "user_name", "Address1", "_rout", etc.
local IdentifierMatcher = {}
IdentifierMatcher.__index = IdentifierMatcher
function IdentifierMatcher.new()
    local self = setmetatable({}, IdentifierMatcher)
    return self
end
function IdentifierMatcher:init(options)
    return self:getNextStep("", options, true)
end
function IdentifierMatcher:getNextStep(history, options, first)
    return function(char, index, result)
        if (string.match(char, "%a") or string.match(char, "_") or (not first and string.match(char, "%d"))) then
            result.matching[#result.matching+1] = self:getNextStep(history .. char, options, false)
        else
            if (#history > 0) then
                result.success[#result.success+1] = {value = history, index = index, token = tokens.IDENTIFIER}
            else
                result.failures[#result.failures+1] = {value = self, message = "No letters found."}
            end
        end
        return result
    end
end

-- Matches against a specific list of passed in keywords such as "new", "return" etc. 
-- It will not match the new in "newName"
local KeywordMatcher = {}
KeywordMatcher.__index = KeywordMatcher
function KeywordMatcher.new(words)
    local self = setmetatable({}, KeywordMatcher)
    self.words = words
    return self
end
function KeywordMatcher:init(options)
    return self:getNextStep("", options, FuncTable.new(self.words), 1)
end
function KeywordMatcher:getNextStep(history, options, matchingWords, offset)
    return function(char, index, result)
        if (string.match(char, "%a")) then
            local continue = false
            local matched = matchingWords:filter(
            function(_, word)
                if (offset <= #word and string.sub(word, offset, offset) == char) then
                    continue = true
                    return 0
                else
                    return 1
                end
            end
            )
            if (continue) then
                result.matching[#result.matching+1] = self:getNextStep(history .. char, options, matched, offset + 1)
            else
                result.failures[#result.failures+1] = {value = self, message = "No matching Keywords found."}
            end
        else
            local success = false
            for _, matching in pairs(matchingWords) do
                if (#matching == offset - 1) then
                    result.success[#result.success+1] = {value = matching, index = index, token = tokens.KEYWORD}
                    success = true
                end
            end
            if (success ~= true) then
                result.failures[#result.failures+1] = {value = self, message = "No letters found."}
            end
        end
        return result
    end
end

-- Matches passed in operators and can match composits such as "+=" or "++"
local OperatorMatcher = {}
OperatorMatcher.__index = OperatorMatcher
function OperatorMatcher.new(operators)
    local self = setmetatable({}, OperatorMatcher)
    self.operators = operators
    return self
end
function OperatorMatcher:init(options)
    return self:getNextStep("", options, FuncTable.new(self.operators), 1, false)
end
function OperatorMatcher:getNextStep(history, options, matchingOperators, offset, found)
    return function(char, index, result)
        local continue = false
        local matched = matchingOperators:filter(
        function(_, operator)
            if (offset <= #operator and string.sub(operator, offset, offset) == char) then
                continue = true
                return 0
            else
                if (offset - 1 == #operator) then
                    found = true
                    result.success[#result.success+1] = {value = operator, index = index, token = tokens.OPERATOR}
                end
                return 1
            end
        end
        )
        if (continue) then
            result.matching[#result.matching+1] = self:getNextStep(history .. char, options, matched, offset + 1, found)
        else
            if (not found) then
                result.failures[#result.failures+1] = {value = self, message = "No matching operators found."}
            end
        end
        return result
    end
end

-- Matches whitespace, mostly so you can ignore it but if you're making something like Python
-- you'll probably have to modify this, and make a <tab> matcher    
local WhitespaceMatcher = {}
WhitespaceMatcher.__index = WhitespaceMatcher
function WhitespaceMatcher.new()
    local self = setmetatable({}, WhitespaceMatcher)
    return self
end
function WhitespaceMatcher:init(options)
    return self:getNextStep("", options)
end
function WhitespaceMatcher:getNextStep(history, options)
    return function(char, index, result)
        if (string.match(char, "%s")) then
            result.matching[#result.matching+1] = self:getNextStep(history .. char, options)
        else
            if (#history > 0) then
                result.success[#result.success+1] = {value = history, index = index, token = tokens.WHITESPACE}
            else
                result.failures[#result.failures+1] = {value = self, message = "No whitespace found."}
            end
        end
        return result
    end
end

-- Matches integers such as '5' '10' '10023240121244'
local IntegerMatcher = {}
IntegerMatcher.__index = IntegerMatcher
function IntegerMatcher.new()
    local self = setmetatable({}, IntegerMatcher)
    return self
end
function IntegerMatcher:init(options)
    return self:getNextStep("", options)
end
function IntegerMatcher:getNextStep(history, options)
    return function(char, index, result)
        if (string.match(char, "%d")) then
            result.matching[#result.matching+1] = self:getNextStep(history .. char, options)
        else
            if (#history > 0) then
                result.success[#result.success+1] = {value = history, index = index, token = tokens.INTEGER}
            else
                result.failures[#result.failures+1] = {value = self, message = "No whitespace found."}
            end
        end
        return result
    end
end

-- Matches floating point numbers such as '3.0', '23435.232345'
-- It will not match "6." since that could be a period or dot
local FloatMatcher = {}
FloatMatcher.__index = FloatMatcher
function FloatMatcher.new()
    local self = setmetatable({}, FloatMatcher)
    return self
end
function FloatMatcher:init(options)
    return self:getNextStep("", options, -1)
end
function FloatMatcher:getNextStep(history, options, pnt)
    return function(char, index, result)
        if (char == "." and pnt < 0) then
            result.matching[#result.matching+1] = self:getNextStep(history .. char, options, 0)
        elseif (string.match(char, "%d")) then
            if (pnt > -1) then pnt = pnt + 1 end
            result.matching[#result.matching+1] = self:getNextStep(history .. char, options, pnt)
        else
            if (#history > 0 and pnt > 0) then
                result.success[#result.success+1] = {value = history, index = index, token = tokens.FLOAT}
            else
                result.failures[#result.failures+1] = {value = self, message = "No float found."}
            end
        end
        return result
    end
end

-- Used in testing, matches all things Lua thinks of as punctuation marks. 
local PunctuationMatcher = {}
PunctuationMatcher.__index = PunctuationMatcher
function PunctuationMatcher.new()
    local self = setmetatable({}, PunctuationMatcher)
    return self
end
function PunctuationMatcher:init(options)
    return self:getNextStep("", options)
end
function PunctuationMatcher:getNextStep(history, options)
    return function(char, index, result)
        if (string.match(char, "%p")) then
            result.matching[#result.matching+1] = self:getNextStep(history .. char, options)
        else
            if (#history > 0) then
                result.success[#result.success+1] = {value = history, index = index, token = tokens.PUNCTUATION}
            else
                result.failures[#result.failures+1] = {value = self, message = "No punctuation found."}
            end
        end
        return result
    end
end

--------------------------------- 
--
-- Tokenizer
--
---------------------------------

local Lexx = {}
Lexx.__index = Lexx
function Lexx.new(text, matchers, options)
    local self = setmetatable({}, Lexx)
    self.text = text
    self.index = 1
    self.options = options
    self.matcherList = FuncTable.new(matchers)
    self.previous = nil
    self.next = 0
    self.longestMatch = nil
    self.root = self
    return self
end
function Lexx.newState(previous, options, index, longestMatch)
    local self = setmetatable({}, {__index = previous.root})
    self.index = index
    self.options = options
    self.previous = previous
    self.longestMatch = longestMatch
    self.next = 0
    return self
end
function Lexx:internalMatch(result, index)
    local char = string.sub(self.text, index, index)
    local newResult = result.matching:foldRight({matching = FuncTable.new({}), success = result.success, failures = result.failures},
    function(foldResult, _, matcher)
        return matcher(char, index, foldResult)
    end
    )
    if (#newResult.matching == 0) then
        return newResult
    end
    return self:internalMatch(newResult, index + 1)
end
function Lexx:getNext()
    if (self.next ~= 0 and self.next ~= nil) then
        return self.next
    end
    local matching = self.matcherList:map(
        function(_, matcher)
            return matcher:init(self.options)
        end
    )
    self.result = self:internalMatch({matching = matching, success = {}, failures = {}}, self.index)
    local longestResult = FuncTable.new(self.result.success):foldRight({max = 0, match = nil},
    function(result, _, testMatch)
        if (#testMatch.value > result.max) then
            result.match = testMatch
            result.max = #testMatch.value
        end
        return result
    end
    )
    if (longestResult.match ~= nil) then
        self.next = Lexx.newState(self, self.options, longestResult.match.index, longestResult.match)
        return self.next
    end
    self.next = Lexx.newState(self, self.options, self.index, nil)
    return self.next
end


--------------------------------- 
--
-- Lexx Tests
--
---------------------------------

local keywordMatcher = KeywordMatcher.new({"new", "for", "return", "function"})
local operatorMatcher = OperatorMatcher.new({"==", "+=", "-", "+", "="})
local lexxTest = nil
local result = nil

-- it can find an identifier
lexxTest = Lexx.new("test", {IdentifierMatcher.new()})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Identifier") end
if (result.longestMatch.token ~= tokens.IDENTIFIER) then print("ERROR: Lexx missidentified Identifier as: " .. result.longestMatch.token) end

-- it can find a more complex identifier
lexxTest = Lexx.new("_test1_2 ", {IdentifierMatcher.new()})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Identifier") end
if (result.longestMatch.token ~= tokens.IDENTIFIER) then print("ERROR: Lexx missidentified Identifier as: " .. result.longestMatch.token) end
if (result.longestMatch.value ~= "_test1_2") then print("ERROR: Lexx failed to parse identifier") end

-- it doesn't find a bad identifier
lexxTest = Lexx.new("1test", {IdentifierMatcher.new()})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Identifier") end
if (result.longestMatch ~= nil) then print("ERROR: Lexx missidentified an invalid Identifier") end

-- it finds spaces
lexxTest = Lexx.new(" ", {WhitespaceMatcher.new()})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Whitespace") end
if (result.longestMatch.token ~= tokens.WHITESPACE) then print("ERROR: Lexx missidentified Whitespace as: " .. result.longestMatch.token) end

-- it finds all spaces
lexxTest = Lexx.new("   ", {WhitespaceMatcher.new()})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Whitespace") end
if (result.longestMatch.token ~= tokens.WHITESPACE) then print("ERROR: Lexx missidentified Whitespace as: " .. result.longestMatch.token) end
if (#result.longestMatch.value ~= 3) then print("ERROR: Lexx did not tokenize all spaces in one block") end

-- it finds spaces between identifiers
lexxTest = Lexx.new("test this", {WhitespaceMatcher.new(), IdentifierMatcher.new()})
result = lexxTest:getNext()
if (result.longestMatch.token ~= tokens.IDENTIFIER) then print("ERROR: Lexx missidentified Identifier as: " .. result.longestMatch.token) end
if (result.longestMatch.value ~= "test") then print("ERROR: Lexx failed to parse identifier 1") end
result = result:getNext()
if (result.longestMatch.token ~= tokens.WHITESPACE) then print("ERROR: Lexx missidentified Whitespace as: " .. result.longestMatch.token) end
result = result:getNext()
if (result.longestMatch.token ~= tokens.IDENTIFIER) then print("ERROR: Lexx missidentified Identifier as: " .. result.longestMatch.token) end
if (result.longestMatch.value ~= "this") then print("ERROR: Lexx failed to parse indentiier 2") end

-- it finds keywords
lexxTest = Lexx.new("new", {keywordMatcher})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Keyword") end
if (result.longestMatch.token ~= tokens.KEYWORD) then print("ERROR: Lexx missidentified Keyword as: " .. result.longestMatch.token) end
if (result.longestMatch.value ~= "new") then print("ERROR: Lexx failed to parse keyword") end

-- it doesn't find a bad keyword
lexxTest = Lexx.new("not", {keywordMatcher})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Keyword") end
if (result.longestMatch ~= nil) then print("ERROR: Lexx missidentified an invalid Keyword") end

-- it doesn't find a keyword that's part of an identifier
lexxTest = Lexx.new("newLexxfunction", {keywordMatcher})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Keyword") end
if (result.longestMatch ~= nil) then print("ERROR: Lexx missidentified an invalid Keyword") end

-- it doesn't find a keyword that's case different
lexxTest = Lexx.new("New", {keywordMatcher})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Keyword") end
if (result.longestMatch ~= nil) then print("ERROR: Lexx missidentified an invalid Keyword") end

-- it finds integers
lexxTest = Lexx.new("5", {IntegerMatcher.new()})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Integer") end
if (result.longestMatch.token ~= tokens.INTEGER) then print("ERROR: Lexx missidentified Integer as: " .. result.longestMatch.token) end

-- it finds big integers
lexxTest = Lexx.new("559383649", {IntegerMatcher.new()})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Integer") end
if (result.longestMatch.token ~= tokens.INTEGER) then print("ERROR: Lexx missidentified Integer as: " .. result.longestMatch.token) end
if (result.longestMatch.value ~= "559383649") then print("ERROR: Lexx failed to parse large integer.") end

-- it finds floats
lexxTest = Lexx.new("6.1", {FloatMatcher.new()})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Float") end
if (result.longestMatch.token ~= tokens.FLOAT) then print("ERROR: Lexx missidentified Float as: " .. result.longestMatch.token) end
if (result.longestMatch.value ~= "6.1") then print("ERROR: Lexx failed to parse Float, got: " .. result.logestMatch.value) end

-- it finds floats, period check
lexxTest = Lexx.new("7.4.", {FloatMatcher.new()})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Float") end
if (result.longestMatch.token ~= tokens.FLOAT) then print("ERROR: Lexx missidentified Float as: " .. result.longestMatch.token) end
if (result.longestMatch.value ~= "7.4") then print("ERROR: Lexx failed to parse Float, got: " .. result.logestMatch.value) end

-- it wont identify floats as integers
lexxTest = Lexx.new("3.1415", {FloatMatcher.new(), IntegerMatcher.new()})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Float") end
if (result.longestMatch.token ~= tokens.FLOAT) then print("ERROR: Lexx missidentified Float as: " .. result.longestMatch.token) end
if (result.longestMatch.value ~= "3.1415") then print("ERROR: Lexx failed to parse bigger float.") end

-- it wont identify float from integer with a period
lexxTest = Lexx.new("96.", {FloatMatcher.new(), IntegerMatcher.new()})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Integer with period") end
if (result.longestMatch.token == tokens.FLOAT) then print("ERROR: Lexx missidentified Integer with period as: " .. result.longestMatch.token) end

-- it finds operators
lexxTest = Lexx.new("==", {operatorMatcher})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Operator") end
if (result.longestMatch.token ~= tokens.OPERATOR) then print("ERROR: Lexx missidentified Operator as: " .. result.longestMatch.token) end
if (result.longestMatch.value ~= "==") then print("ERROR: Lexx failed to parse operator") end

-- it finds operator even if other symbols are attached
lexxTest = Lexx.new("=-", {operatorMatcher})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Operator") end
if (result.longestMatch.token ~= tokens.OPERATOR) then print("ERROR: Lexx missidentified Operator as: " .. result.longestMatch.token) end
if (result.longestMatch.value ~= "=") then print("ERROR: Lexx failed to parse operator") end

-- it finds operator even if other symbols are attached #2
lexxTest = Lexx.new("===", {operatorMatcher})
result = lexxTest:getNext()
if (result == nil) then print("ERROR: Lexx failed to analize Operator") end
if (result.longestMatch.token ~= tokens.OPERATOR) then print("ERROR: Lexx missidentified Operator as: " .. result.longestMatch.token) end
if (result.longestMatch.value ~= "==") then print("ERROR: Lexx failed to parse operator") end

-- test winding back
lexxTest = Lexx.new("This is a test", {WhitespaceMatcher.new(), IdentifierMatcher.new()})
result = lexxTest:getNext()
if (result.longestMatch.value ~= "This") then print("ERROR: Lexx failed to parse identifier This") end
result = result:getNext()
if (result.longestMatch.token ~= tokens.WHITESPACE) then print("ERROR: Lexx missidentified Whitespace as: " .. result.longestMatch.token) end
result = result:getNext()
if (result.longestMatch.value ~= "is") then print("ERROR: Lexx failed to parse indentiier is") end
result = result:getNext()
if (result.longestMatch.token ~= tokens.WHITESPACE) then print("ERROR: Lexx missidentified Whitespace as: " .. result.longestMatch.token) end
result = result:getNext()
if (result.longestMatch.value ~= "a") then print("ERROR: Lexx failed to parse indentiier a") end
result = result:getNext()
if (result.longestMatch.token ~= tokens.WHITESPACE) then print("ERROR: Lexx missidentified Whitespace as: " .. result.longestMatch.token) end
result = result:getNext()
if (result.longestMatch.value ~= "test") then print("ERROR: Lexx failed to parse indentiier test") end
result = result.previous.previous.previous.previous
result.next = 0
result = result:getNext()
if (result.longestMatch.value ~= "is") then print("ERROR: Lexx failed to parse indentiier test") end
result = result:getNext()
if (result.longestMatch.token ~= tokens.WHITESPACE) then print("ERROR: Lexx missidentified Whitespace as: " .. result.longestMatch.token) end

if false then
	-- code from the docs, to make sure it works as advertised :)
	local lexx = Lexx.new("This is a test", {IdentifierMatcher.new(), WhitespaceMatcher.new()})

	lexx = lexx:getNext()
	
	print(lexx.longestMatch.token)
	print(lexx.longestMatch.value)

	lexx = lexx:getNext() 
	print(lexx.longestMatch.token)

	print(lexx.longestMatch.value)

	lexx = lexx:getNext() 
	print(lexx.longestMatch.token)
	print(lexx.longestMatch.value)

	print(lexx.previous.previous.longestMatch.value)

	print(lexx.previous.next.longestMatch.value)
	

	print(lexx.previous:getNext().longestMatch.value)
	

	lexx = lexx.previous
	lexx.next = 0
	lexx = lexx:getNext() -- this forced a re-tokenizing. 
	print(lexx.longestMatch.value)
end

-- long case
local lexxTest = Lexx.new(".1 The lazy dog + thinking about jumping over 1 dead += programmer 42.1 It had been an odd day", {KeywordMatcher.new({"dead", "lazy", "think", "overpowered"}), OperatorMatcher.new({"==", "+=", "-", "+"}), IdentifierMatcher.new(), WhitespaceMatcher.new(), IntegerMatcher.new(), FloatMatcher.new()}, {})

while (lexxTest.index < #lexxTest.text + 1) do
    lexxTest = lexxTest:getNext()
    --print("Lexx index is: " .. lexx.index)
    if (lexxTest == nil) then
        print("No match found.")
        break;
    else
        -- print("Found: " .. lexx.longestMatch.token .. " '" .. lexx.longestMatch.value .. "'")
    end
end

LEXX = {}
LEXX.Lexx = Lexx
LEXX.OperatorMatcher = OperatorMatcher
LEXX.KeywordMatcher = KeywordMatcher
LEXX.LinebreakMatcher = LinebreakMatcher
LEXX.IntegerMatcher = IntegerMatcher
LEXX.FloatMatcher = FloatMatcher
LEXX.IdentifierMatcher = IdentifierMatcher
LEXX.PunctuationMatcher = PunctuationMatcher
LEXX.WhitespaceMatcher = WhitespaceMatcher
LEXX.Tokens = tokens

return LEXX