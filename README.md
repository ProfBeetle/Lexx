# Lexx
A greedy lexical string tokenizer

## What is it?
Lexx takes a string and breaks it into tokens. It's greedy in the sense that it will return
the longest match it finds, but it also returns other matches and failed matches to aid in
debugging (or if you don't want the longest match).

To do so it walks through a text string sending characters to Matchers, when all of the Matchers
have stopped matching it returns the longest successful match.

## Usage
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

For more examples take a look at the tests at the bottom of Lexx.lua
