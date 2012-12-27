> {-# LANGUAGE OverloadedStrings #-}

| In this tutorial you will learn how to use this library. The /Simple example/
section should be enough to get you going, but you can keep reading if you want
to better understand how to deal with complex parsing scenarios.

You may import this module and try the subsequent examples as you go.


> module Control.Proxy.Attoparsec.Tutorial
>   (-- * Simple example
>    -- $example-simple
>
>    -- * Parsing control proxies
>    -- ** Handling parser errors
>    -- $example-errors
>
>    -- ** Composing
>    -- $example-compose-control
>
>    -- ** Roll your own
>    -- $example-control-custom
>
>    -- * Try for yourself
>    -- $example-try
>     Name(..)
>   , hello
>   , input1
>   , input2
>   , helloPipe1
>   , helloPipe2
>   , helloPipe3
>   , helloPipe4
>   , helloPipe5
>   , helloPipe6
>   , skipPartialResults
>   ) where
>
> import Control.Proxy
> import Control.Proxy.Attoparsec
> import Control.Proxy.Trans.Either
> import Data.Attoparsec.Text
> import Data.Text
>
> data Name = Name Text
>           deriving (Show, Eq)
>
> hello :: Parser Name
> hello = fmap Name $ "Hello " .*> takeWhile1 (/='.') <*. "."
>
> input1 :: [Text]
> input1 =
>   [ "Hello Kate."
>   , "Hello Mary.Hello Jef"
>   , "f."
>   , "Hel"
>   , "lo Tom."
>   ]
>
> input2 :: [Text]
> input2 =
>   [ "Hello Amy."
>   , "Hello, Hello Tim."
>   , "Hello Bob."
>   , "Hello James"
>   , "Hello"
>   , "Hello World."
>   , "HexHello Jon."
>   , "H"
>   , "ello Ann"
>   , "."
>   , "Hello Jean-Luc."
>   ]
>
> helloPipe1 :: (Proxy p, Monad m) => () -> Pipe p Text Name m r
> helloPipe1 = parserInputD >-> parserD hello
>
> helloPipe2 :: (Proxy p, Monad m) => () -> Pipe p Text Name m r
> helloPipe2 = parserInputD >-> skipMalformedInput >-> parserD hello
>
> helloPipe3 :: (Proxy p, Monad m) => () -> Pipe (EitherP BadInput p) Text Name m r
> helloPipe3 = parserInputD >-> throwParsingErrors >-> parserD hello
>
> helloPipe4 :: (Proxy p, Monad m) => () -> Pipe (EitherP BadInput p) Text Name m r
> helloPipe4 = parserInputD >-> limitInputLength 10 >-> parserD hello
>
> helloPipe5 :: (Proxy p, Monad m) => () -> Pipe (EitherP BadInput p) Text Name m r
> helloPipe5 = parserInputD >-> limitInputLength 10 >-> skipMalformedInput >-> parserD hello
>
> helloPipe6 :: (Proxy p, Monad m) => () -> Pipe p Text Name m r
> helloPipe6 = parserInputD >-> skipPartialResults >-> parserD hello
>
> skipPartialResults
>  :: (Monad m, Proxy p, AttoparsecInput a)
>  => ParserStatus a
>  -> p (ParserStatus a) (ParserSupply a) (ParserStatus a) (ParserSupply a) m r
> skipPartialResults = runIdentityK . foreverK $ go
>   where go x@(Parsing _) = request x >>= respond . Start . supplyChunk
>         go x             = request x >>= respond


$example-simple

We'll write a simple 'Parser' that turns 'Text' like /“Hello John Doe.”/
into @'Name' \"John Doe\"@, and then make a 'Pipe' that turns
those 'Text' values flowing downstream into 'Name' values flowing
downstream using that 'Parser'.

In this example we are using 'Text', but we may as well use
'Data.ByteString.ByteString'. Also, the 'OverloadedStrings' language
extension lets us write our parser easily.

  > {-# LANGUAGE OverloadedStrings #-}
  >
  > import Control.Proxy
  > import Control.Proxy.Attoparsec
  > import Control.Proxy.Trans.Either
  > import Data.Attoparsec.Text
  > import Data.Text
  >
  > data Name = Name Text
  >           deriving (Show)
  >
  > hello :: Parser Name
  > hello = fmap Name $ "Hello " .*> takeWhile1 (/='.') <*. "."

We are done with our parser, now lets make a simple parsing 'Pipe' with it.

  > helloPipe1 :: (Proxy p, Monad m) => () -> Pipe p Text Name m r
  > helloPipe1 = parserInputD >-> parserD hello

As the type indicates, this 'Pipe' recieves 'Text' values from upstream and
sends 'Name' values downstream. This 'Pipe' is made of two smaller
two smaller cooperating 'Proxy's:

  1. 'parserInputD': Prepares @a@ input received from upstream to be
     consumed by a downstream parsing 'Proxy'.

  2. 'parserD': Repeatedly runs a given @'Parser' a b@ on input 'a' from
     upstream, and sends 'b' values downstream.

We need some sample input to test our simple 'helloPipe1'.

  > input1 :: [Text]
  > input1 =
  >   [ "Hello Kate."
  >   , "Hello Mary.Hello Jef"
  >   , "f."
  >   , "Hel"
  >   , "lo Tom."
  >   ]

We'll use @'fromListS' input1@ as our input source, which sends
downstream one element from the list at a time. We'll call each of these
elements a /chunk/. So, @'fromListS' input1@ sends 5 /chunks/ of
'Text' downstream.

Notice how some of our /chunks/ are not, by themselves, complete inputs
for our 'hello' 'Parser'. This is fine; we want to be able to feed the
'Parser' with either partial or complete input as soon as it's
received from upstream. More input will be requested when needed.
Attoparsec's 'Parser' handles partial parsing just fine.

  >>> runProxy $  fromListS input1 >-> helloPipe1 >-> printD
  Name "Kate"
  Name "Mary"
  Name "Jeff"
  Name "Tom"

We have acomplished our simple goal: We've made a 'Pipe' that parses
downstream flowing input using our 'Parser' 'hello'.


$example-errors

Let's try with some more complex input.

  > input2 :: [Text]
  > input2 =
  >   [ "Hello Amy."
  >   , "Hello, Hello Tim."
  >   , "Hello Bob."
  >   , "Hello James"
  >   , "Hello"
  >   , "Hello World."
  >   , "HexHello Jon."
  >   , "H"
  >   , "ello Ann"
  >   , "."
  >   , "Hello Jean-Luc."
  >   ]

  >>> runProxy $ fromListS input2 >-> helloPipe1 >-> printD
  Name "Amy"
  Name "Bob"
  Name "JamesHelloHello World"
  Name "Ann"
  Name "Jean-Luc"

The simple @helloPipe1@ we built skips /chunks/ of input that fail to be
parsed, and then continues parsing new input. That approach might be
enough if you are certain your input is always well-formed, but
sometimes you may prefer to act differently on these extraordinary
situations.

Instead of just using 'parserInputD' and 'parserD' to build our
'helloPipe1', we could have used an additional 'Proxy' in beween them to
handle these situations. The module "Control.Proxy.Attoparsec.Control"
exports some useful 'Proxy's that serve this purpose. The default
behavior just mentioned resembles the one provided by
'skipMalformedChunks'.

Here are some other examples:

['skipMalformedInput']
  Skips single /pieces of the malformed chunk/, one at a time, until parsing
  succeds. It requests a new input from upstream if needed. Compare this
  behavior with that of 'skipMalformedChunks', which skips /the entire
  malformed chunk/.

  > helloPipe2 :: (Proxy p, Monad m) => () -> Pipe p Text Name m r
  > helloPipe2 = parserInputD >-> skipMalformedInput >-> parserD hello

  >>> runProxy $ fromListS input2 >-> helloPipe2 >-> printD
  Name "Amy"
  Name "Tim"
  Name "Bob"
  Name "JamesHelloHello World"
  Name "Jon"
  Name "Ann"
  Name "Jean-Luc"

['throwParsingErrors']
  When a parsing error arises, aborts execution by throwing
  'MalformedInput' in the 'EitherP' proxy transformer.

  > helloPipe3 :: (Proxy p, Monad m) => () -> Pipe (EitherP BadInput p) Text Name m r
  > helloPipe3 = parserInputD >-> throwParsingErrors >-> parserD hello

  >>> runProxy . runEitherK $ fromListS input2 >-> helloPipe3 >-> printD
  Name "Amy"
  Left (MalformedInput {miParserErrror = ParserError {errorContexts = [], errorMessage = "Failed reading: takeWith"}})

[@'limitInputLength' n@]
  If a @'Parser' a b@ has consumed input @a@ of length longer than
  @n@ without producing a @b@ value, and it's still requesting more
  input, then throw 'InputTooLong' in the 'EitherP' proxy transformer.

  > helloPipe4 :: (Proxy p, Monad m) => () -> Pipe (EitherP BadInput p) Text Name m r
  > helloPipe4 = parserInputD >-> limitInputLength 10 >-> parserD hello

  >>> runProxy . runEitherK $ fromListS input2 >-> helloPipe4 >-> printD
  Name "Amy"
  Name "Bob"
  Left (InputTooLong {itlLenght = 11})

  Notice that by default, as mentioned earlier, parsing errors are
  ignored by skipping the malformed /chunk/. That's why we didn't get any
  complaint about the malformed input between /“Amy”/ and /“Bob”/.


$example-compose-control

These 'Proxy's that control the parsing behavior can be easily plugged
together with @('>->')@ to achieve a combined functionality, Keep in
mind that the order in which these 'Proxy's are used is important.

Suppose you don't want to parse inputs of length longer than 10, and you
also want to skip /small bits of malformed input/.

  > helloPipe5 :: (Proxy p, Monad m) => () -> Pipe (EitherP BadInput p) Text Name m r
  > helloPipe5 = parserInputD >-> limitInputLength 10 >-> skipMalformedInput >-> parserD hello

  >>> runProxy . runEitherK $ fromListS input2 >-> helloPipe5 >-> printD
  Name "Amy"
  Name "Tim"
  Name "Bob"
  Left (InputTooLong {itlLenght = 11})


$example-control-custom

In case the parsing control 'Proxy's provided by
"Control.Proxy.Attoparsec.Control" are not enough for your needs, you
can easily roll your own.

A parsing control 'Proxy' receives a @'ParserStatus' a@ from downstream
reporting the status of a 'parserD' parsing 'Proxy', and in exchange it should
respond with a @'ParserSupply' a@ value, which holds both the input to be
parsed and directives on whether the current parsing activity should be resumed
using the given input, or if instead, a new 'Parser' should be started and the
input fed to it. Any of these values might be changed on their way through this
new 'Proxy'. See the documentation about 'ParserStatus' and 'ParserSupply' for
more details.

Suppose you want to write a parsing control 'Proxy' that never provides
additional input to partial parsing results. Let's first take a look at the
type of this 'Proxy':

  > skipPartialResults
  >  :: (Monad m, Proxy p, AttoparsecInput a)
  >  => ParserStatus a
  >  -> p (ParserStatus a) (ParserSupply a) (ParserStatus a) (ParserSupply a) m r

Remember, a parsing control 'Proxy' just forwards @'ParserStatus' a@ values
upstream and @'ParserSupply' a@ values downstream, optionaly replacing them by
new values. In our case, if we receive @'Parsing' n@ from downstream, then we
know there is a partial parsing result waiting for more input. If we were to
respond to this request with a @'Resume' a@ value, then the partial parsing
would continue, but if we change our response to @'Start' a@, then the partial
parsing would be aborted and a new parsing activity would start consuming the
given input. The code is straigthforward:

  > skipPartialResults = runIdentityK . foreverK $ go
  >   where go x@(Parsing _) = request x >>= respond . Start . supplyChunk
  >         go x             = request x >>= respond

We forward upstream the request we got from downstream, then we use
'supplyChunk' to extract the input /chunk/ from a @'ParserSupply' a@ received
from upstream, and finally we use 'Start' to construct our new desired
@'ParserSupply' a@ value before responding.

Now we can use this parsing control 'Proxy' with some simple input and see it
working.

  > helloPipe6 :: (Proxy p, Monad m) => () -> Pipe p Text Name m r
  > helloPipe6 = parserInputD >-> skipPartialResults >-> parserD hello

  >>> runProxy $ fromListS input1 >-> helloPipe6 >-> printD
  Name "Kate"
  Name "Mary"


$example-try

This module exports the following previous examples so that you can try
them.

