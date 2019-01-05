## names

We distinguish between the following types of transitions:
  * An _advance_ pushes a new state onto the stack.

idea: To encode nonterminal expansions with only one choice (i.e. `A` in `S -> x A y`) where the expansion of `A` is **not** optional but has to happen exactly once anyways, introduce a `TryLookaheadAction` that doesn't throw on empty lookahead cells, but simply does nothing.

---------

On merging states: In LR, there are only two kinds of transition: shift and reduce. shift can always be merged as a default action, because it rejects invalid terminal symbols itself. reduce can only be merged if the reduced production is already being reduced in this state for a different lookahead. Adding new productions might end up in a different stack state and alter the language of the grammar, but reducing on additional lookaheads is fine.
Reason: the lookahead check before a reduce is redundant. After every reduce there is *always* another shift immediately following it. (visually speaking: in the AST, there exists another terminal node to the right of every nonterminal node, except for the root (which is still followed by `$`))

## Literature

[IELR]: https://people.cs.clemson.edu/~malloy/publications/papers/scp09/scp09.pdf
