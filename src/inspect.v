fn inspect() {
	mut idx := u64(0)
	for ; idx < tokens.len ; idx++ {
		match tokens[idx].tok {
			.func {
				idx = inspect_function(idx)
			}
			else {
				assert false, "unexpected toplevel token"
			}
		}
	}
}

struct StackVar {
	tok u64
	loc u64
//	size u64
}

struct Function {
mut:
	name u64
	argc u64
	retc u64

	idx_start u64
	idx_end u64

	string_lits []u64

	stackvars []StackVar
	stackframe u64
}

__global function_list = []Function{}
__global has_main = false
__global tokens = []Token{}

fn (f StackVar) str() string {
	return 'StackVar{
    tok: ${name_strings[tokens[f.tok].usr1]}
    loc: $f.loc
}'
}

fn (f Function) str() string {
	mut slit := '['
	for i, s in f.string_lits {
		slit += "'${name_strings[s]}'"
		if i < f.string_lits.len - 1 {
			slit += ', '
		}
	}
	slit += ']'
	return
'Function{
    name: ${name_strings[f.name]}
    argc: ${f.argc}
    retc: ${f.retc}
    idx_start: ${f.idx_start}
    idx_end: ${f.idx_end}
    string_lits: $slit
    stackvars: $f.stackvars
    stackframe: $f.stackframe
}'
}

fn inspect_function(_idx u64) u64 {
	mut idx := _idx

	mut func := Function{}
	tokens[idx].usr1 = u64(function_list.len)

	idx++
	assert idx < tokens.len, "unexpected EOF when parsing function"
	assert tokens[idx].tok == .name, "function name must not be an intrinsic"
	// assert name_strings[tokens[idx].usr1][0] != `_`, "function name must not contain a leading underscore"
	if name_strings[tokens[idx].usr1] == 'main' {
		has_main = true
	}
	for f in function_list {
		assert name_strings[f.name] != name_strings[tokens[idx].usr1], "duplicate function name"
	}
	func.name = tokens[idx].usr1

	idx++
	assert idx < tokens.len, "unexpected EOF when parsing function"

	if tokens[idx].tok == .number_lit {
		argc_tok := idx
		idx += 2
		assert idx < tokens.len, "unexpected EOF when parsing function argument and return counts"
		assert tokens[argc_tok].tok == .number_lit && tokens[argc_tok+1].tok == .number_lit, "argument and return counts must be numbers"
		func.argc = tokens[argc_tok    ].usr1
		func.retc = tokens[argc_tok + 1].usr1

		assert func.argc <= 6, "function must not accept more that 6 arguments"
		assert func.retc <= 6, "function must not return more that 6 arguments"
	}
	assert tokens[idx].tok == .do_block, "no do block keyword located"
	
	/* func.idx_start = idx
		// idx must point to do block because it will be incremented
		// just like idx end pointing to .endfunc
	*/

	idx++
	assert idx < tokens.len, "unexpected EOF when parsing function"

	func.idx_start = idx

	for ; idx < tokens.len ; idx++ {
		match tokens[idx].tok {
			.endfunc {
				func.idx_end = idx // for pos < idx_end
				break
			}
			else {
				idx = inspect_one(idx, mut func)
			}
		}
	}

	function_list << func
	return idx // do not skip over .endfunc, will be incremented anyway
}

fn inspect_one(_idx u64, mut func Function) u64 {
	mut idx := _idx
	match tokens[idx].tok {
		.if_block {
			mut elsep := u64(0)
			mut broken := false
			
			idx++ // skip if
			
			for ; idx < tokens.len ; idx++ {
				match tokens[idx].tok {
					.else_block {
						assert elsep == 0, "if statement cannot contain multiple else blocks"
						elsep = idx
					}
					.endif_block {
						broken = true
						break
					}
					else {
						idx = inspect_one(idx, mut func)
					}
				}
			}

			assert broken, "EOF when parsing if statement"

			if elsep != 0 {
				tokens[_idx].usr1 = elsep
				tokens[elsep].usr1 = idx
				tokens[idx].usr1 = 0
			} else {
				tokens[_idx].usr1 = idx
				tokens[idx].usr1 = 0
			}

			// if -> else -> endif -> 0
		}
		.while_block {
			mut broken := false
			mut dop := u64(0)

			idx++

			for ; idx < tokens.len ; idx++ {
				match tokens[idx].tok {
					.do_block {
						assert dop == 0, "while statement cannot contain multiple do blocks"
						dop = idx
					}
					.endwhile_block {
						broken = true
						break
					}
					else {
						idx = inspect_one(idx, mut func)
					}
				}
			}

			assert broken, "EOF when parsing while statement"
			assert dop != 0, "while statement does not contain a body (do block)"

			tokens[_idx].usr1 = dop
			tokens[dop].usr1 = idx
			tokens[idx].usr1 = 0

			// while  -> do -> endwhile -> 0
		}
		._asm {
			assert idx + 3 <= tokens.len &&
				tokens[idx+1].tok == .number_lit && 
				tokens[idx+2].tok == .number_lit &&
				tokens[idx+3].tok == .string_lit, "asm expects numbers being inputs and outputs with a string literal as the 3 next tokens"
			
			idx += 3 // skip over
		}
		.reserve {
			assert idx + 2 <= tokens.len &&
				tokens[idx+1].tok == .number_lit && 
				tokens[idx+2].tok == .name, "reserve keyword must contain a number and a buf name"

			for f in func.stackvars {
				assert name_strings[tokens[f.tok].usr1] != name_strings[tokens[idx+2].usr1], "duplicate function name"
			}

			// don't want UB because unaligned stack
			
			align := fn (n u64) u64 {
				return ((n + 7) & ~(7))
			}
			
			func.stackframe += align(tokens[idx+1].usr1)
			func.stackvars << StackVar {
				tok: idx + 2
				loc: func.stackframe
			//	size: tokens[idx+1].usr1
			}

			idx += 2
		}
		.string_lit {
			func.string_lits << idx
		}
		.func {
			assert false, "cannot define a function inside a function"
		}
		else {}
	}
	return idx
}