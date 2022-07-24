struct Parser {
mut:
	s Scanner // contains file + error handling
	
	tokens []Token
	curr Token
	pos int
	cap int

	has_main bool

	fns map[string]&IR_function
	ctx &IR_function

	inside_if    bool
	inside_while bool
}

fn (mut g Parser) iter(){
	g.pos++
	if g.pos >= g.cap {
		g.s.error_tok("unexpected EOF", g.curr) 
	}
	g.curr = g.tokens[g.pos]
}

fn (mut g Parser) next(expected Tok){
	g.iter()
	if g.curr.token != expected {
		g.s.error_tok("expected $expected, got $g.curr.token",g.curr)
	}
}

fn (mut g Parser) current(expected Tok){
	if g.curr.token != expected {
		g.s.error_tok("expected $expected, got $g.curr.token",g.curr)
	}
}

fn (mut g Parser) next_bool(expected Tok) bool {
	g.iter()
	return g.curr.token == expected
}

fn str_to_u64(s string)u64{
	if s[0] == `-` {
		return -s[1..].u64()
	} else {
		return s.u64()
	}
}

fn (mut g Parser) new_push()IR_Statement{
	if g.curr.token == .name {
		if g.curr.lit in g.fns {
			g.ctx.is_stack_frame = true
			g.trace("new func call '$g.curr.lit'")
			return IR_CALL_FUNC {
				argc: g.fns[g.curr.lit].args.len
				func: g.curr.lit
			}
		}
		if g.ctx.get_var(g.curr.lit) {
			g.trace("new push var '$g.curr.lit'")
			return IR_PUSH_VAR {
				var: g.curr.lit
			}
		} else {
			g.s.error_tok("Variable or function '$g.curr.lit' not found",g.curr)
		}
	}

	if g.curr.token == .string_lit {
		hash := unsafe { new_lit_hash() }
		g.ctx.slit[hash] = g.curr
		return IR_PUSH_STR_VAR {
			var: hash
		}
	} else if g.curr.token == .number_lit {
		return IR_PUSH_NUMBER {
			data: str_to_u64(g.curr.lit)
		}
	}

	g.s.error_tok("Expected literal data or variable, got '$g.curr.token'",g.curr)
}

fn (mut g Parser) check_exists(tok Token){
	if g.ctx == unsafe { nil } {
		return
	}

	if tok.lit in g.fns {
		g.s.error_tok("Name is already function '$tok.lit'",tok)
	} else if tok.lit in g.ctx.args {
		g.s.error_tok("Name is already a function argument '$tok.lit'",tok)
	} else if tok.lit in g.ctx.vars {
		g.s.error_tok("Duplicate variable '$tok.lit'",tok)
	}
}

fn (mut g Parser) eof_cleanup(){
	// done parsing all, parse_func should not be called anymore

	if !g.has_main {
		g.s.error_whole("No main function")
	}

	assert !g.inside_if
	assert !g.inside_while

	g.trace("eof cleanup")
}

fn (mut g Parser) new_stack_var()IR_Statement{
	g.next(.name)
	name_tok := g.curr
	g.check_exists(name_tok)
	g.trace("new stack var '$name_tok.lit'")
	g.iter()

	if g.curr.token !in [.string_lit, .number_lit] {
		if g.curr.token == .name && g.ctx.get_var(g.curr.lit) {
			g.ctx.vars[name_tok.lit] = VarT {g.curr,g.ctx.vari}
			g.ctx.vari++
		}
		g.s.error_tok("Expected literal data or variable, got '$g.curr.token'",g.curr)
	} else {
		g.ctx.vars[name_tok.lit] = VarT {g.curr,g.ctx.vari}
		g.ctx.vari++
	} // change this lol duplicated code twice

	if g.curr.token == .string_lit {
		hash := unsafe { new_lit_hash() }
		g.ctx.slit[hash] = g.curr
		return IR_VAR_INIT_STR {
			var: name_tok.lit
			data: hash
		}
	} else if g.curr.token == .number_lit {
		return IR_VAR_INIT_NUMBER {
			var: name_tok.lit
			data: str_to_u64(g.curr.lit)
		}
	}

	panic("")

	/* return IR_VAR_INIT{
		var: name_tok.lit
	} */
}

fn (mut g Parser) parse_new_func()?{
	g.current(.name)
	name := g.curr
	g.trace("new func '$name.lit'")
	g.next(.in_block)

	g.check_exists(name)

	if name.lit == "main" {
		g.has_main = true
	}
	g.ctx = &IR_function{}
	g.ctx.name = name.lit
	g.fns[g.ctx.name] = g.ctx

	for g.next_bool(.name) {
		g.check_exists(g.curr)
		g.ctx.args << g.curr.lit
	}
	assert g.ctx.args.len <= 6 
		// 'limitation' of fastcall
	g.trace("args func '$name.lit', $g.ctx.args")
	g.current(.do_block)

	for {
		if i := g.parse_token() {
			g.ctx.body << i
		} else {
			if g.curr.token == .end_block {
				g.trace("end func '$name.lit'")
				if g.pos+1 >= g.cap {
					return error('')
				} else {
					g.iter()
				}
				return
			}
			g.s.error_tok("function does not end",g.curr)
		}
	}
	panic("")
}

[if parser_trace?]
fn (mut g Parser) trace(str string){
	eprintln("TRACE -- $str")
}

fn (mut g Parser) parse_if()IR_if{
	g.trace("new if")

	mut ctx := IR_if{}
	g.inside_if = true
	defer {g.inside_if = false}

	for {
		if i := g.parse_token() {
			ctx.top << i
		} else {
			if g.curr.token == .do_block {
				g.trace("end if args")
				break
			}
			g.s.error_tok("starting statement in if does not end",g.curr)
		}
	}

	for {
		if i := g.parse_token() {
			ctx.body << i
		} else {
			if g.curr.token == .else_block {
				for {
					if i := g.parse_token() {
						ctx.other << i
					} else {
						if g.curr.token == .end_block {
							g.trace("end if else")
							break
						} else {
							g.s.error_tok("if statement does not end",g.curr)
						}
					}
				}
				break
			} else if g.curr.token == .end_block {
				g.trace("end if")
				break
			} else {
				g.s.error_tok("if statement does not end",g.curr)
			}
		}
	}

	return ctx
}

fn (mut g Parser) parse_while()IR_while{
	g.trace("new while")

	mut ctx := IR_while{}
	g.inside_while = true
	defer {g.inside_while = false}

	for {
		if i := g.parse_token() {
			ctx.top << i
		} else {
			if g.curr.token == .do_block {
				g.trace("end while args")
				break
			}
			g.s.error_tok("starting statement in while does not end",g.curr)
		}
	}

	for {
		if i := g.parse_token() {
			ctx.body << i
		} else {
			if g.curr.token == .end_block {
				g.trace("end while")
				break
			} else {
				g.s.error_tok("while loop does not end",g.curr)
			}
		}
	}

	return ctx
}

fn (mut g Parser) parse_token()?IR_Statement{
	for {
		g.pos++
		if g.pos >= g.cap {
			return none
		}
		g.curr = g.tokens[g.pos]

		match g.curr.token {
			.local {
				return g.new_stack_var()
			}

			.print   {return IR_PRINT{} }
			.println {return IR_PRINTLN{} }
			.uput    {return IR_UPUT{} }
			.uputln  {return IR_UPUTLN{} }

			/* .pop {
				g.iter()
				var := g.get_var(g.curr)
				if var.spec == .declare {
					g.s.error_tok("Declared variables are immutable",g.curr)
				}
				
				// like i said above, do basic typechecking
				return IR_POP{
					var: g.curr.lit
				}
			} */

			.add     {return IR_ADD{}}
			.sub     {return IR_SUB{}}
			.mul     {return IR_MUL{}}
			.div     {return IR_DIV{}}
			.mod     {return IR_MOD{}}
			.divmod  {return IR_DIVMOD{}}
			.inc     {return IR_INC{}}
			.dec     {return IR_DEC{}}
			.greater {return IR_GREATER{}}
			.less    {return IR_LESS{}}
			.equal   {return IR_EQUAL{}}
			.ret     {return IR_RETURN{}}
			.dup     {return IR_DUP{}}
			.drop    {return IR_DROP{}}

			.name, .number_lit, .string_lit {
				return g.new_push()
			}

			.if_block {
				return g.parse_if()
			}
			.while_block {
				return g.parse_while()
			}
			.else_block {
				if g.inside_if {
					return none
				} else {
					g.s.error_tok("unexpected else while not inside if",g.curr)
				}
			}


			.end_block {
				return none
				/* if g.inside_if && g.inside_if */
			}

			.do_block {
				if g.inside_if || g.inside_while {
					return none
				} else {
					g.s.error_tok("unexpected keyword",g.curr)
				}
			}

			else {panic("Parser not exaustive! 'Tok.$g.curr.token'")}
		}
		break
	}
	return none
}
