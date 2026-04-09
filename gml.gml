// gml.gml -- A GML parser and interpreter within GML itself, in a single script
// by kenan238
// Modify at your own risk!

/* 
========================= 
========= SETUP ========= 
========================= 

You have to call gml_init() to initialize it.

=====================
======= DOC =========
=====================

-> gml_run: Runs code from a given GML code string, you can provide a "self" that will act as the current
			scope that the code will run in. 
			You can also pass in a gmlVMScript to run with some additional settings.
			
			!! WARNING !! This doesn't perform any sort of caching, this means that GML.gml will spend time parsing
			and compiling the code. If you ever want to repeatedly run a given snippet, use gml_parse and gml_vm respectively.
			
			!! NOTE !! This basically calls gml_parse and gml_vm.
	* Returns: 0 by default, or whatever has been returned by the code, or Error
			
-> gml_parse: This will return the parsed result from a given GML code string. This is basically the "compiled" code, and what
			gets run by gml_vm. You'd usually call this function to parse a snippet once, and cache it somewhere to
			run it multiple times.
	* Returns: gmlBlockNode or Error
	
-> gml_vm: This will actually execute the output of gml_parse, you can provide a "self" that will act as the current
			scope that the code will run in, alongside an "other" (they're basically the self and other variables).
			You can also pass in a gmlVMScript to run with some additional settings.
	* Returns: 0 by default, or whatever has been returned by the code, or Error
	
-> gml_test: Like gml_run, but only takes a code string and expects a specific return value.

(You can check whether a function returned an error by calling `gml_is_error`)

-> gmlVMScript: A constructor that holds runtime information and settings for the VM.
	* AddBlacklist(asset1, asset2, ...): Adds a script or an object to the VM blacklist.
						 This will ensure a given:
						- Script can't be called or resolved.
						- Object can't have its variables accessed or can't be resolved.



======================== 
======= EXAMPLES ======= 
======================== 

// Running code
var result = gml_run("return 1 + 1")
trace(result) // 2

// Running code with caching
var compiled = gml_parse(@"
var k = 1
while (k <= 255)
	k *= 2
	
return k
")
var result = gml_vm(compiled)
trace(result) // 729

// Running code under a custom context, with blacklisting
var scpt = new gmlVMScript()
scpt.AddBlacklist(trace)
var result = gml_run("trace(a_var)", { a_var: 1 }, scpt) // error (can't use trace)
trace(gml_is_error(result)) // 1


======================== 
========= NOTE ========= 
======================== 

==> If you think you're knowledgeable enough to use a function, you can do so at your own risk.
==> For any feature requests, contact me some way:
    -> Github: kenan238
    -> Discord: kenan238
*/

#region utilities

#region character stuff
function ch_is_numeric(ch)
{
	var o = ord(ch)
	return o >= ord("0") && o <= ord("9")
}

function ch_is_octal(ch)
{
	var o = ord(ch)
	return o >= ord("0") && o <= ord("7")
}

function ch_is_alpha(c)
{
    if c == "_"
        return true
    
    var o = ord(c);
    if o >= ord("a") && o <= ord("z")
        return true;
    if o >= ord("A") && o <= ord("Z")
        return true;
    return false;
}

function ch_is_alphanumeric(c)
{
	return ch_is_numeric(c) || ch_is_alpha(c)
}

function ch_is_hex(c)
{
    var o = ord(c);
    
    // a-f range
    if o >= ord("a") && o <= ord("f")
        return true;
    if o >= ord("A") && o <= ord("F")
        return true;
    
    return ch_is_numeric(c)
}
#endregion

function gml_util_struct_copy(from, to)
{
    var names = struct_get_names(from)
    for (var i = 0; i < array_length(names); i++)
    {
        var na = names[i]
        var va = from[$ na];
        to[$ na] = va;
    }
}

function struct_map(struct, predicate)
{
	var names = struct_get_names(struct)
	for (var i = 0; i < array_length(names); i++)
	{
		var name = names[i]
		struct[$ name] = predicate(struct[$ name])
	}
	
	return struct;
}

function array_extend(array, elements)
{
    if !is_array(elements)
        elements = [elements]
    
    for (var i = 0; i < array_length(elements); ++i)
        array_push(array, elements[i])
}

function array_slice(array, top, tail)
{
	var cpy = []
	array_copy(cpy, 0, array, top, tail - top)
	return cpy;
}

function trace()
{
    var sb = ""
    for (var i = 0; i < argument_count; i++)
        sb += string(argument[i])
        
	show_debug_message(sb)
    
    return argument[0];
}

function is_equal(a)
{
    for (var i = 1; i < argument_count; i++)
    {
        if (argument[i] == a)
            return true;
    }
    
    return false;
}
#macro is is_equal
#endregion

// don't pollute global
function __gml_global()
{
	
} __gml_global();
#macro __gml __gml_global

enum token_type
{
	open_paren,
	close_paren,
	number,
	
    plus,
	minus,
	multiply,
	divide,
	modulo,
	bit_lshift,
	bit_rshift,
    nullcoalesce,
    
    increment, 
    decrement, 
    
    v_and, 
    v_or, 
    v_xor, 
    v_negate, 
	
    text, 
	
    open_bracket, 
	close_bracket, 
	
    comma, 
	dot, 
	symbol, 
	equal, 
	func, 
	
    open_brace, 
	close_brace, 
	
    k_if, 
	k_else, 
	k_while, 
	k_for, 
    k_repeat, 
    k_return, 
    k_exit,
    k_new, 
    k_constructor,
    k_enum,
    
    k_continue, 
    k_break, 
    k_throw, 
    k_try, 
    k_catch, 
    
    k_switch, 
    k_case, 
    k_default, 
    
    k_var, 
    k_static, 
    k_with, 
    k_do,
    k_until,
    k_globalvar,
    k_finally,
    k_then, 
    k_delete, 
	
    semicolon, 
    qmark,
    dollar,
    at,
    hash,
	
    b_equal, 
	b_nequal, 
    plus_equal, 
    minus_equal, 
    times_equal, 
    divide_equal,
    or_equal,
    and_equal,
    xor_equal,
    modulo_equal,
    
    nullcoalesce_equal,
	
    biggerthan, 
	lessthan, 
	
    b_biggereq, 
	b_lesseq, 
	
    negate, 
	b_and, 
    b_or, 
    
    colon, 
    
    eof 
}

function gml_token_name(type)
{
    switch (type)
    {
        case token_type.open_paren: return "open_paren"; break;
        case token_type.close_paren: return "close_paren"; break;
        case token_type.number: return "number"; break;
        case token_type.plus: return "plus"; break;
        case token_type.minus: return "minus"; break;
        case token_type.multiply: return "multiply"; break;
        case token_type.divide: return "divide"; break;
        case token_type.modulo: return "modulo"; break;
        case token_type.bit_lshift: return "bit_lshift"; break;
        case token_type.bit_rshift: return "bit_rshift"; break;
        case token_type.nullcoalesce: return "nullcoalesce"; break;
        case token_type.increment: return "increment"; break;
        case token_type.decrement: return "decrement"; break;
        case token_type.v_and: return "v_and"; break;
        case token_type.v_or: return "v_or"; break;
        case token_type.v_xor: return "v_xor"; break;
        case token_type.v_negate: return "v_negate"; break;
        case token_type.text: return "text"; break;
        case token_type.open_bracket: return "open_bracket"; break;
        case token_type.close_bracket: return "close_bracket"; break;
        case token_type.comma: return "comma"; break;
        case token_type.dot: return "dot"; break;
        case token_type.symbol: return "symbol"; break;
        case token_type.equal: return "equal"; break;
        case token_type.func: return "func"; break;
        case token_type.open_brace: return "open_brace"; break;
        case token_type.close_brace: return "close_brace"; break;
        case token_type.k_if: return "k_if"; break;
        case token_type.k_else: return "k_else"; break;
        case token_type.k_while: return "k_while"; break;
        case token_type.k_for: return "k_for"; break;
        case token_type.k_repeat: return "k_repeat"; break;
        case token_type.k_return: return "k_return"; break;
        case token_type.k_exit: return "k_exit"; break;
        case token_type.k_new: return "k_new"; break;
        case token_type.k_constructor: return "k_constructor"; break;
        case token_type.k_enum: return "k_enum"; break;
        case token_type.k_continue: return "k_continue"; break;
        case token_type.k_break: return "k_break"; break;
        case token_type.k_throw: return "k_throw"; break;
        case token_type.k_try: return "k_try"; break;
        case token_type.k_catch: return "k_catch"; break;
        case token_type.k_switch: return "k_switch"; break;
        case token_type.k_case: return "k_case"; break;
        case token_type.k_default: return "k_default"; break;
        case token_type.k_var: return "k_var"; break;
        case token_type.k_static: return "k_static"; break;
        case token_type.k_with: return "k_with"; break;
        case token_type.k_do: return "k_do"; break;
        case token_type.k_until: return "k_until"; break;
        case token_type.semicolon: return "semicolon"; break;
        case token_type.qmark: return "qmark"; break;
        case token_type.dollar: return "dollar"; break;
        case token_type.at: return "at"; break;
        case token_type.hash: return "hash"; break;
        case token_type.b_equal: return "b_equal"; break;
        case token_type.b_nequal: return "b_nequal"; break;
        case token_type.plus_equal: return "plus_equal"; break;
        case token_type.minus_equal: return "minus_equal"; break;
        case token_type.biggerthan: return "biggerthan"; break;
        case token_type.lessthan: return "lessthan"; break;
        case token_type.b_biggereq: return "b_biggereq"; break;
        case token_type.b_lesseq: return "b_lesseq"; break;
        case token_type.negate: return "negate"; break;
        case token_type.b_and: return "b_and"; break;
        case token_type.b_or: return "b_or"; break;
        case token_type.colon: return "colon"; break;
        case token_type.eof: return "eof"; break;
    }
    
    throw $"gml_token_name failed unknown type {type}"
}

function gmlStringConsumer(str) constructor
{
	// ;)
	str = string_replace_all(string_replace_all(str, "\r\n", "\n"), "\r", "") + "\n"
	
	self.buf = buffer_create(string_length(str), buffer_grow, 1)
	buffer_seek(self.buf, buffer_seek_start, 0)
	buffer_write(self.buf, buffer_string, str)
	
	self.backbuffer = undefined
	self.backindex = 0
	
	self.index = 0
    
    self.column = 0
    self.line = 1
	
    static Offload = function (buf)
    {
        var tempbuf = buffer_create(string_length(buf), buffer_fixed, 1)
        buffer_write(tempbuf, buffer_text, buf)
        self.SetTemporaryBuffer(tempbuf)
    }
    
    static SetTemporaryBuffer = function (tempbuf)
    {
    	self.backbuffer = self.buf;
    	self.buf = tempbuf;
    	self.backindex = self.index;
    	self.index = 0;
    }
    
    static ResetTemporaryBuffer = function ()
    {
    	buffer_delete(self.buf)
    	self.buf = self.backbuffer;
    	self.backbuffer = undefined;
    	self.index = self.backindex;
    	self.backindex = 0;
    }
    
    static ReadingTempBuffer = function ()
    {
    	return !is_undefined(self.backbuffer);
    }
    
    static At = function (idx)
    {
    	if (!self.CanRead())
    		return " "
    		
    	return chr(buffer_peek(self.buf, idx, buffer_u8))
    }
    
	static Consume = function ()
	{
		if !self.CanRead()
			throw "Unexpected end of file"
			
        self.column++
        var ch = self.At(self.index);
        self.index++;
        
        if (ch == "\n")
        {
            self.column = 0;
            self.line++;
        }
        
        if (self.ReadingTempBuffer() && !self.CanRead())
        {
        	self.ResetTemporaryBuffer();
        }
        
		return ch;
	}
    
    static GetPosition = function ()
    {
        return {
            column: self.column,
            line: self.line
        };
    }
    
    static Forward = function (len = 1)
    {
        repeat len
        {
            self.Consume();
        }
    }
    
    static ConsumeSymbol = function (symb = "")
    {
        while ch_is_alphanumeric(self.Peek())
            symb += self.Consume();
        
        return symb;
    }
	
	static Peek = function (off = 0)
	{
		return self.At(self.index + off)
	}
	
    static PeekMany = function (len = 1)
    {
        var sb = "";
        for (var i = 0; i < len; i++)
            sb += self.At(self.index + i);
        
        return sb;
    }
    
	static CanRead = function ()
	{
		return self.index < buffer_get_size(self.buf)
	}
	
	static Dispose = function ()
	{
		buffer_delete(self.buf)
	}
}

enum token_value
{
	real,
	string,
	nothing,
}

function gmlTokenizer(consumer) constructor
{
	self.consumer = consumer;
	
	self.available_tokens = ds_queue_create()
    self.macros = {};
    
	static Dispose = function ()
	{
		self.consumer.Dispose();
		ds_queue_destroy(self.available_tokens)
	}
	
	static Push = function (token)
	{
		token[2] = consumer.GetPosition()
		ds_queue_enqueue(self.available_tokens, token)
	}
	
	static TryFill = function (amount)
	{
		while amount-- > 0
		{
			var old = ds_queue_size(self.available_tokens)
			
			while (ds_queue_size(self.available_tokens) - old) == 0 && self.consumer.CanRead()
				self.ParseToken(self.consumer)
		}
	}
	
	static PopAvailable = function ()
	{
		return ds_queue_dequeue(self.available_tokens) ?? [token_type.eof, 0, { column: 0, line: 0 }]
	}
	
	self.TryFill(2)
	
	self.next_token = self.PopAvailable()
	self.next_next_token = self.PopAvailable()
	
	static Depleted = function ()
	{
		return self.next_token[0] == token_type.eof;
	}
	
	static Advance = function ()
	{
		if self.Depleted()
		{
			return;
		}
		
		self.next_token = self.next_next_token
		self.TryFill(1)
		self.next_next_token = self.PopAvailable()
	}
	
	static Consume = function ()
	{
		var tok = self.next_token
		self.Advance()
		return tok;
	}
	
	static ParseString = function (ch, type = "normal")
	{
	    var sb = ""
	    while (consumer.Peek() != ch)
	    {
	        var consumed = consumer.Consume();
	        
	        if (string_count("\n", consumed) > 0) && type != "multiline"
	            throw $"Found newline within string: {sb}"
	        else if consumed == "{" && type == "dollar"
	        {
	            self.Push([token_type.text, sb]);
	            sb = "";
	
	            // hackiest hack in town
	            self.Push([token_type.plus])
	            self.Push([token_type.symbol, "string"])
	            self.Push([token_type.open_paren])
	
	            while (consumer.Peek() != "}")
	                self.ParseToken(consumer);
	            
	            if consumer.Peek() != "}"
	                throw "No closing brace inside of dollar-string"
	        
	            consumer.Consume(); // }
	        
	            self.Push([token_type.close_paren])
	            self.Push([token_type.plus])
	            continue;
	        }
	    
	        if (consumed == "\\")
	        {
	            // escaping string
	            var esc_chr = consumer.Consume();
	            
	            switch (esc_chr)
	            {
	            case "n": consumed = "\n"; break;
	            case "r": consumed = "\r"; break;
	            case "b": consumed = "\b"; break;
	            case "f": consumed = "\f"; break;
	            case "t": consumed = "\t"; break;
	            case "v": consumed = "\v"; break;
	            case "a": consumed = "\a"; break;
	            // I don't get the difference between these 2
	            case "x": 
	                consumed = chr(self.ParseHex()); 
	                break;
	            case "u":
	                consumed = chr(self.ParseHex());
	                break;
	            
	            default:
	                if esc_chr == "0"
	                {
	                    consumed = chr(self.ParseOctal());
	                    break;
	                }
	                
	                // add the escaped char literally
	                consumed = esc_chr;
	                break;
	            }
	        }
	        
	        sb += consumed;
	    }
	        
	    if (consumer.Consume() != ch)
	        throw "Unterminated string"
	    
	    return sb;
	}

	static PatternCheck = function ()
	{
		if (argument_count % 2 != 0)
	        throw "PatternCheck fail";
	    
	    for (var i = 0; i < argument_count; i += 2)
	    {
	        var pat = argument[i], p_len = string_length(pat);
	        var tok = argument[i + 1];
	        
	        if (consumer.PeekMany(p_len) == pat)
	        {
	            consumer.Forward(p_len)
	            return tok;
	        }
	    }
	    
	    __args_toarray1
	    throw $"PatternCheck didn't match any: {_args}: {consumer.PeekMany(p_len)}";
	}
	
	static ParseNumber = function (cur = "", is_decimal_shorthand = false)
	{
		var digit = ""
		
		// .XXX decimal shorthand
		if !is_decimal_shorthand && ch_is_numeric(cur)
			digit = cur
		else
			digit = "0."
			
		while ch_is_numeric(consumer.Peek()) || consumer.Peek() == "."
			digit += consumer.Consume();
			
		return real(digit)
	}
	
	static ParseHex = function ()
	{
	    var nb = "";
	    while ch_is_hex(consumer.Peek())
	        nb += consumer.Consume();
	    
	    return real("0x" + nb);
	}
	
	static ParseOctal = function ()
	{
	    var sb = "";
	    while ch_is_octal(consumer.Peek())
	        sb += consumer.Consume();
	    
	    var octal = 0, p = 0;
	    for (var i = string_length(sb); i > 0; i--)
	    {
	        var ch = real(string_char_at(sb, i))
	        var d = ch * power(8, p++)
	        octal += d;
	    }
	    
	    return octal;
	}
	
	static ParseToken = function (consumer)
	{
	    var ch = consumer.Consume();
	    
	    while ch == " "
	    	ch = consumer.Consume();
	    
		switch ch
		{
			case "(": self.Push([token_type.open_paren]); break;
			case ")": self.Push([token_type.close_paren]); break;
			case "[": self.Push([token_type.open_bracket]); break;
			case "]": self.Push([token_type.close_bracket]); break;
			case "{": self.Push([token_type.open_brace]); break;
			case "}": self.Push([token_type.close_brace]); break;
			case "!":
				if consumer.Peek() == "="
				{
					consumer.Consume();
					self.Push([token_type.b_nequal]);
					break;
				}
				self.Push([token_type.negate]);
				break;
			case "=":
				if consumer.Peek() == "="
				{
					consumer.Consume();
					self.Push([token_type.b_equal]);
					break;
				}
				self.Push([token_type.equal]); 
				break;
			case ".":
				if (ch_is_numeric(consumer.Peek()))
				{
					self.Push([ token_type.number, self.ParseNumber(ch, true) ]);
					break;
				}
				self.Push([token_type.dot]); 
				break;
			case ",": self.Push([token_type.comma]); break;
			case "+": self.Push([ self.PatternCheck("=", token_type.plus_equal, "+", token_type.increment, "", token_type.plus) ]); break;
			case "-": self.Push([ self.PatternCheck("=", token_type.minus_equal, "-", token_type.decrement, "", token_type.minus) ]); break;
			case "*": self.Push([ self.PatternCheck("=", token_type.times_equal, "", token_type.multiply) ]); break;
			case "/": 
	            if (consumer.Peek() == "/")
	            {
	                // comment
	                consumer.Consume(); // slash
	                
	                while consumer.Peek() != "\n"
	                    consumer.Consume();
	                
	                consumer.Consume(); // the newline
	                break;
	            }
	            if (consumer.Peek() == "*")
	            {
	                // multiline comment
	                consumer.Consume(); // star
	                
	                while consumer.PeekMany(2) != "*/"
	                    consumer.Consume();
	                
	                repeat 2 // star and slash
	                    consumer.Consume();
	                break;
	            }
	            self.Push([ self.PatternCheck("=", token_type.divide_equal, "", token_type.divide) ]); 
	            break;
			case "%": self.Push([ self.PatternCheck("=", token_type.modulo_equal, "", token_type.modulo) ]); break;
			case ";": self.Push([token_type.semicolon]); break;
			case ":": self.Push([token_type.colon]); break;
			case "#": 
	            if (consumer.PeekMany(6) == "region" || consumer.PeekMany(9) == "endregion")
	            {
	                // ignore regions
	                while consumer.Peek() != "\n"
	                    consumer.Consume();
	                
	                break
	            }
	            else if (consumer.PeekMany(5) == "macro")
	            {
	                consumer.Forward(5); // skip the word macro
	                
	                if (consumer.Peek() != " ")
	                    throw "Macro definition missing spacing before name"
	                
	                while consumer.Peek() == " "
	                    consumer.Consume(); // space
	                
	                var macroname = consumer.ConsumeSymbol();
	                
	                if (consumer.Peek() != " ")
	                    throw "Macro definition missing spacing after name"
	                consumer.Consume(); // space
	                
	                var macrostring = "";
	                
	                while consumer.Peek() != "\n"
	                    macrostring += consumer.Consume();
	                
	                trace($"Registered {macroname}: {macrostring}")
	                self.macros[$ macroname] = macrostring;
	                break;
	            }
	            self.Push([token_type.hash]); 
	            break;
			case "?": self.Push([ self.PatternCheck("?=", token_type.nullcoalesce_equal, "?", token_type.nullcoalesce, "", token_type.qmark) ]); break;
			
	        case "$": 
			case "@": 
	            if is(consumer.Peek(), "'", "\"")
	            {
	                var quote = consumer.Consume();
	                self.Push([token_type.text, self.ParseString(quote, ch == "@" ? "multiline" : "dollar")])
	            }
	            else
	                self.Push([ch == "@" ? token_type.at : token_type.dollar])
	            break;
			
			case ">": 
				self.Push([ self.PatternCheck("=", token_type.b_biggereq, ">", token_type.bit_rshift, "", token_type.biggerthan) ]); 
				break;
			case "<": 
				self.Push([ self.PatternCheck("=", token_type.b_lesseq, "<", token_type.bit_lshift, "", token_type.lessthan) ]); 
				break;
				
			case "&": 
	            self.Push([ self.PatternCheck("&", token_type.b_and, "=", token_type.and_equal, "", token_type.v_and) ]) 
				break;
	        
	        case "|":
	            self.Push([ self.PatternCheck("|", token_type.b_or, "=", token_type.or_equal, "", token_type.v_or) ])
	            break;
	        
	        case "^": self.Push([ self.PatternCheck("=", token_type.xor_equal, "", token_type.v_xor) ]) break;
	        case "~": self.Push([token_type.v_negate]) break;
	        
			case "\"":
			case "'":
	            var sb = self.ParseString(ch);
	            self.Push([token_type.text, sb])
				break;
			
			default:
				if ch_is_numeric(ch)
	            {
	                var nb = 0;
	                
	                if ch == "0" && consumer.Peek() == "x"
	                {
	                    consumer.Consume(); // x
	                    nb = self.ParseHex();
	                }
	                else
	                    nb = self.ParseNumber(ch);
	                
	                self.Push([token_type.number, nb]);
	            }
					
				if ch_is_alpha(ch)
				{
					var symb = consumer.ConsumeSymbol(ch);
	                
	                // macro handling
	                if struct_exists(self.macros, symb)
	                {
	                    // this is a macro
	                    // fixes for toString and such
	                    var macro = self.macros[$ symb]
	                    if is_string(macro)
	                    {
	                    	consumer.Offload(macro)
	                    	break;
	                    }
	                }
						
					switch symb
					{
					// keywords
					case "function": self.Push([token_type.func]); break;
					case "if": self.Push([token_type.k_if]); break;
					case "else": self.Push([token_type.k_else]); break;
					case "while": self.Push([token_type.k_while]); break;
					case "for": self.Push([token_type.k_for]); break;
					case "repeat": self.Push([token_type.k_repeat]); break;
					case "new": self.Push([token_type.k_new]); break;
					case "constructor": self.Push([token_type.k_constructor]); break;
					case "var": self.Push([token_type.k_var]); break;
					case "static": self.Push([token_type.k_static]); break;
					case "return": self.Push([token_type.k_return]); break;
					case "exit": self.Push([token_type.k_exit]); break;
					case "switch": self.Push([token_type.k_switch]); break;
					case "case": self.Push([token_type.k_case]); break;
					case "default": self.Push([token_type.k_default]); break;
					case "begin": self.Push([token_type.open_brace]); break;
					case "end": self.Push([token_type.close_brace]); break;
					case "then": self.Push([token_type.k_then]) break;
					case "delete": self.Push([token_type.k_delete]) break;
					case "and": self.Push([token_type.b_and]); break;
					case "or": self.Push([token_type.b_or]); break;
					case "not": self.Push([token_type.negate]); break;
					case "div": self.Push([token_type.divide]); break;
					case "mod": self.Push([token_type.modulo]); break;
					case "continue": self.Push([token_type.k_continue]); break;
					case "break": self.Push([token_type.k_break]); break;
					case "throw": self.Push([token_type.k_throw]); break;
					case "try": self.Push([token_type.k_try]); break;
					case "catch": self.Push([token_type.k_catch]); break;
					case "with": self.Push([token_type.k_with]); break;
					case "do": self.Push([token_type.k_do]); break;
					case "until": self.Push([token_type.k_until]); break;
					case "enum": self.Push([token_type.k_enum]); break;
					case "globalvar": self.Push([token_type.k_globalvar]); break;
					case "finally": self.Push([token_type.k_finally]); break;
	                
					default:
						self.Push([token_type.symbol, symb]);
						break
					}
				}
				break;
		} 
	}

}

#region AST node definitions
function gmlNode() constructor 
{
    self.pos = __gml.last_tokenpos;
    
    static Fold = function ()
    {
    	return self;
    }
    
    static Traverse = function (visitor)
    {
    	static walk = function (value)
    	{
    		if (!visitor(value))
    			return;
    		if is_array(value)
    		{
    			for (var i = 0; i < array_length(value); i++)
    				walk(value[i])
    		}
    		else if is_instanceof(value, gmlBlockNode)
    		{
    			for (var i = 0; i < array_length(value.statements); i++)
    				walk(value.statements[i])
    		}
    		else if is_struct(value) && !is_method(value)
    		{
    			var names = struct_get_names(value);
    			for (var i = 0; i < array_length(names); i++)
    				walk(value[$ names[i]])
    		}
    	}
    	
    	var wlk_self = { visitor }, meth = __gml_method_real(wlk_self, walk);
    	wlk_self.walk = meth;
    	meth(self);
    }
    
    static Execute = function (ctx)
    {
    }
}

function gmlLeafNode(d) : gmlNode() constructor
{
	self.data = d
	
	static Execute = function (ctx)
	{
		return self.data;
	}
}
function gmlOpNode(op, lhs = undefined, rhs = undefined) : gmlNode() constructor
{
	self.op = op
	self.lhs = lhs
	self.rhs = rhs
	self.Execute = __gml_method_real(self, __gml_get_op(self.op));
    
	static Fold = function ()
	{
		self.lhs = self.lhs.Fold();
		self.rhs = self.rhs.Fold();
		
		// attempt to fold
		if is_instanceof(self.lhs, gmlLeafNode) && is_instanceof(self.rhs, gmlLeafNode)
		{
			var final = 0;

    		switch (self.op)
		    {
		    case token_type.plus: final = lhs.data + rhs.data; break;
		    case token_type.minus: final = lhs.data - rhs.data; break;
		    case token_type.divide: final = lhs.data / rhs.data; break;
		    case token_type.multiply: final = lhs.data * rhs.data; break;
		    case token_type.modulo: final = lhs.data % rhs.data; break;
		    case token_type.nullcoalesce: final = lhs.data ?? rhs.data; break;
		    case token_type.lessthan: final = lhs.data < rhs.data; break;
		    case token_type.biggerthan: final = lhs.data > rhs.data; break;
		    case token_type.b_and: final = lhs.data && rhs.data; break;
		    case token_type.b_or: final = lhs.data || rhs.data; break;
		    case token_type.b_equal: final = lhs.data == rhs.data; break;
		    case token_type.b_lesseq: final = lhs.data <= rhs.data; break;
		    case token_type.b_biggereq: final = lhs.data >= rhs.data; break;
		    case token_type.b_nequal: final = lhs.data != rhs.data; break;
		    case token_type.v_or: final = lhs.data | rhs.data; break;
		    case token_type.v_and: final = lhs.data & rhs.data; break;
		    case token_type.v_xor: final = lhs.data ^ rhs.data; break;
		    case token_type.bit_lshift: final = lhs.data << rhs.data; break;
		    case token_type.bit_rshift: final = lhs.data >> rhs.data; break;
		    case token_type.equal: final = lhs.data == rhs.data; break; // stinky legacy
		    }
		    
		    return new gmlLeafNode(final)
		}
		return self;
	}
	
	static Execute = function (ctx)
    {
        throw "Must call the normal scope Execute function"
    }
}
function gmlArrayNode(children) : gmlNode() constructor
{
	self.children = children
	
	static Fold = function ()
	{
		for (var i = 0; i < array_length(self.children); i++)
			self.children[i] = self.children[i].Fold()
			
		return self;
	}
	
	static Execute = function (ctx)
	{
		var arr = []
        for (var i = 0; i < array_length(self.children); i++)
        {
            var el = self.children[i]
            array_push(arr, gml_vm_expr(el, ctx))
        }
        
        return arr;
	}
}
function gmlStructNode(struct) : gmlNode() constructor 
{
    self.data = struct
    
    static Fold = function()
    {
    	struct_map(self.data, function (el)
    	{
    		return el.Fold();
    	})
    	
    	return self;
    }
    
    static Execute = function (ctx)
    {
    	var flat = {}
        var keys = struct_get_names(self.data)
        var struct_ctx = new gmlVMContext(ctx.script, flat, ctx.scope, ctx.gm_function).Extend(ctx);
        
        for (var i = 0; i < array_length(keys); i++)
        {
            var key = keys[i]
            var v = gml_vm_expr(self.data[$ key], struct_ctx);
            
            // assign function to this struct
            gml_vm_func_bind_selfscope(v, struct_ctx.scope)
            
            flat[$ key] = v
        }
        
        return flat;
    }
}
function gmlVarNode(name) : gmlNode() constructor
{
	self.name = name;
	
	static Fold = function ()
	{
		var builtin = gml_vm_builtin(self.name)
		if gml_vm_builtin.found
			return new gmlLeafNode(builtin)
		
		return self;
	}
    
    self.lvalue = new gmlLValue(function (ctx) 
	{
		// cache scope location here
		if (node.scope_location == undefined)
			node.scope_location = ctx.FindVarScope(node.name);
		return ctx.GetVar(node.name, node.scope_location)
	}, function (value, ctx) 
	{
		// and here also
		if (node.scope_location == undefined)
			node.scope_location = ctx.FindVarScope(node.name);
		ctx.SetVar(node.name, value, node.scope_location)
    	return value;
	});
	self.lvalue.node = self;
	
	self.lastctx = undefined;
	
    self.scope_location = undefined;
	
	// caches are applicable here since when a variable is typically defined its going to stay in the same scope
	// since they cant be deleted
	
	static Execute = function (ctx)
	{
		if (self.lastctx != ctx)
		{
			// updated context so we need to recompute stuff
			self.lastctx = ctx;
			if (self.scope_location != global)
				self.scope_location = undefined; // reset
		}
		
		return self.lvalue;
	}
}
function gmlAccessNode(node, index, how) : gmlNode() constructor 
{
    self.node = node;
    self.index = index;
    self.how = how;
    
    // unbind them so they run in the context that theyre put in within the execute method
    self.getfunc = __gml_method_real(undefined, __gml_vm_get_access_func(self.how))
    self.setfunc = __gml_method_real(undefined, __gml_vm_set_access_func(self.how))
    
    self.lvalue = new gmlLValue(function (ctx)
    {
    	__gml_profile("Access")
    	__gml_vm_access_checklegal(root, ctx)
    	var f = node.getfunc // cuz dot notation changes scope..
    	var r = f(ctx)
    	__gml_endprofile("Access")
    	return r;
    }, function (value, ctx)
    {
    	__gml_profile("Access")
    	__gml_vm_access_checklegal(root, ctx)
    	gml_vm_func_bind_selfscope(root, value)
    	var f = node.setfunc // cuz dot notation changes scope..
    	var r = f(value, ctx)
    	__gml_endprofile("Access")
    	return r;
    });
    self.lvalue.node = self;
    
    static Fold = function ()
    {
    	self.node = self.node.Fold();
    	
    	if !is_string(self.index)
    	{
	    	if !is_array(self.index)
	    		self.index = self.index.Fold();
	    	else
	    		self.index = array_map(self.index, function (el)
	    		{
	    			return el.Fold();
	    		})
    	}
    		
    	return self;
    }
    
    static Execute = function (ctx)
    {
    	var root = gml_vm_expr(self.node, ctx);
    	
		self.lvalue.root = root;
        
        return self.lvalue;
    }
}
function gmlFunctionNode(name, arg_names, block, is_constructor, inherit_call = undefined, arg_optionals = {}) : gmlNode() constructor
{
    self.name = name;
	self.arg_names = arg_names
    self.arg_optionals = arg_optionals
	self.block = block
    self.is_constructor = is_constructor
    self.inherit_call = inherit_call
    
    static Decouple = function ()
    {
    	self.name = ""
    	return self;
    }
    
    static Fold = function ()
    {
    	struct_map(self.arg_optionals, function (el)
    	{
    		return el.Fold();
    	})
    	
    	self.block = self.block.Fold();
    	
    	if self.is_constructor && !is_undefined(self.inherit_call)
    		self.inherit_call = self.inherit_call.Fold()
    	return self;
    }
    
    static Execute = function (ctx)
    {
        var func_meta = {
            is_constructor: self.is_constructor,
            
            arg_names: self.arg_names,
            arg_optionals: self.arg_optionals,
            
            inherit_call: self.inherit_call,
            block: self.block,
            name: self.name,
            
            scopes_filled: false,
            _self: undefined,
            
            statics: {},
        };
        
        // make the actual function
        func_meta.base_ctx = ctx;
        
        var fn = __gml_method_real(func_meta, func_meta.is_constructor ? __gml_vm_fun_construct : __gml_vm_fun)
        
        func_meta[$ gml_func_sig] = true;
        func_meta.fn = fn;
        
        // do not re-run this piece of code for functions that have been preinited as top level ones
        // probably make this not run at all? idk
        if string_length(self.name) > 0 && !ctx.HasFunc(self.name)
        {
            if !ctx.in_constructor
            {
                // assigned as a script-wide function
                var new_meta = {}
                gml_util_struct_copy(func_meta, new_meta)
                gml_vm_func_clearscope(new_meta)
                ctx.SetFunc(self.name, __gml_method_real(new_meta, fn));
            }
            else // bind it to the parent constructor
                gml_vm_func_bind_selfscope(fn, ctx.scope)
            
            ctx.SetVar(self.name, fn, ctx.scope);
        }
        return fn;
    }
}

function gmlCallNode(node, params) : gmlNode() constructor
{
	self.node = node
	self.params = params
	self.is_new = false;
	
	static Fold = function ()
	{
		self.node = self.node.Fold();
		for (var i = 0; i < array_length(self.params); i++)
			self.params[i] = self.params[i].Fold();
		
		// try to possibly resolve calls on compile
		if is_instanceof(self.node, gmlLeafNode)
		{
			var funcdata = self.node.data;
			var leaves = [], all_leaves = true;
			
			// scan all arguments
			for (var i = 0; i < array_length(self.params); i++)
			{
				var par = self.params[i]
				if is_instanceof(par, gmlLeafNode)
					array_push(leaves, par.data)
				else
				{
					all_leaves = false;
					break;
				}
			}
			
			var funcname = script_get_name(funcdata)
			
			if all_leaves && is(funcname, "chr", "ord", "power", "method", "nameof", "typeof", "struct_exists", "struct_get", "instanceof", "string", "real", "int64", "is_real", "is_string", "is_struct")
			{
				var callchk = __gml_call(funcdata, leaves);
				return new gmlLeafNode(callchk)
			}
		}
		
		return self;
	}
	
	static Execute = function (ctx)
	{
		var func = gml_vm_expr(self.node, ctx), is_new = self.is_new;
        
        if ctx.script.IsBlacklisted(int64(func))
        	throw $"Can't call blacklisted function: {script_get_name(func)}"
        
        var funcself = method_get_self(func);
        
        if is_struct(funcself) && struct_get(funcself, "name") == "gml_vm_cache_assettype"
            return;
        
        var values = [];
        array_copy(values, 0, self.params, 0, array_length(self.params))
        
        for (var i = 0; i < array_length(values); i++)
            values[i] = gml_vm_expr(values[i], ctx)
            
    	__gml_vm_expr_checkcall(func, values, ctx)
        
        if !is(typeof(func), "method", "ref", "int64", "number")
            throw $"Expected method for call but got {typeof(func)}: {func}"
        
        with ctx.scope_other
        {
            with ctx.scope
                return __gml_call(func, values, is_new)
        }
	}
}
function gmlNegateNode(node) : gmlNode() constructor
{
    self.node = node;
    
    static Fold = function ()
    {
    	self.node = self.node.Fold();
    	
    	if is_instanceof(self.node, gmlLeafNode)
    		return new gmlLeafNode(!self.node.data)
    	
    	return self;
    }
    
    static Execute = function (ctx)
    {
    	var value = gml_vm_expr(self.node, ctx)
        return !value;
    }
}
function gmlBitNegateNode(node) : gmlNode() constructor
{
    self.node = node;
    
    static Fold = function ()
    {
    	self.node = self.node.Fold();
    	
    	if is_instanceof(self.node, gmlLeafNode)
    		return new gmlLeafNode(~self.node.data)
    	
    	return self;
    }
    
    static Execute = function (ctx)
    {
    	var value = gml_vm_expr(self.node, ctx)
        return ~value;
    }
}
function gmlDoUntilStatementNode(cond, block) : gmlNode() constructor 
{
    self.cond = cond;
    self.block = block;
    
    static Fold = function ()
    {
    	self.cond = self.cond.Fold();
    	self.block = self.block.Fold();
    	
    	if is_instanceof(self.cond, gmlLeafNode) && self.cond.data
    		return new gmlNode(); // kill useless do untils
    	
    	return self;
    }
    
    static Execute = function (ctx)
    {
    	var cond = self.cond, block = self.block;
        
        do {
        	var k = gml_vm_block(block, ctx);
            if is_instanceof(k, VMInterrupt)
            {
                if (k.type == token_type.k_continue)
                    continue;
                else if (k.type == token_type.k_break)
                    break;
                else
                    return k; // send interrupt up 
            }
        } until (gml_vm_expr(cond, ctx))
    }
}
function gmlIncrementNode(node, pre, val = 1) : gmlNode() constructor 
{
    self.node = node;
    self.pre = pre;
    self.val = val;
    
    static Fold = function ()
    {
    	self.node = self.node.Fold();
    	
    	return self;
    }
    
    static PreExecute = function (ctx)
    {
    	var lv = gml_vm_expr_lvalue(self.node, ctx)
        var v = lv.Get(ctx);
        
        return lv.Set(v + self.val, ctx);
    }
    
    static PostExecute = function (ctx)
    {
    	var lv = gml_vm_expr_lvalue(self.node, ctx)
        var v = lv.Get(ctx);

        lv.Set(v + self.val, ctx)
        return v;
    }
    
    self.Execute = self.pre ? self.PreExecute : self.PostExecute;
    
    static Execute = function (ctx)
    {
        throw $"Wrong Execute func called for increment"
    }
}

function gmlVarStatementNode(name, value, type = token_type.k_var) : gmlNode() constructor 
{
    self.name = name;
    self.value = value;
    self.type = type;
    
    static Fold = function ()
    {
    	if !is_undefined(self.value)
    		self.value = self.value.Fold();
    	
    	return self;
    }
    
    static Execute = function (ctx)
    {
    	var val = is_undefined(self.value) ? self.value : gml_vm_expr(self.value, ctx);
        
        if (self.type == token_type.k_static)
            ctx.SetStaticVar(self.name, val)
        else if (self.type == token_type.k_globalvar)
        {
        	// globalvars declarations with no values only create globalvars if they dont exist
        	// so if it doesnt have a value to it and it already exists then its useless
        	
        	if is_undefined(self.value) 
        	{
        		if !variable_global_exists(self.name)
        		{
        			variable_global_set(self.name, undefined)
        		}
        	}
        	else
        		ctx.SetVar(self.name, val, global);
        }
        else
            ctx.SetVar(self.name, val, ctx.locals);
    }
}

function gmlConditionalStatementNode(cond_expr, blk, type, elsebranch = undefined) : gmlNode() constructor
{
	self.cond_expr = cond_expr
	self.block = blk
	self.type = type
    self.elsebranch = elsebranch
    
    static Fold = function ()
    {
    	self.cond_expr = self.cond_expr.Fold();
    	self.block = self.block.Fold();
    	
    	if !is_undefined(self.elsebranch)
    		self.elsebranch = self.elsebranch.Fold();
    		
    	if is_instanceof(self.cond_expr, gmlLeafNode) && !self.cond_expr.data
    		return new gmlNode(); // kill useless conditionals
    		
    	return self;
    }
    
    static Execute = function (ctx)
    {
    	var expr = self.cond_expr, block = self.block, type = self.type;
        
        switch (type)
        {
        case token_type.k_if:
            if (gml_vm_expr(expr, ctx))
            {
                var k = gml_vm_block(block, ctx);
                if !is_undefined(k)
                    return k;
            }
            else if !is_undefined(self.elsebranch)
            {
                var k = gml_vm_block(self.elsebranch, ctx);
                if !is_undefined(k)
                    return k;
            }
            break;
            
        case token_type.k_while:
            while (gml_vm_expr(expr, ctx))
            {
                var k = gml_vm_block(block, ctx);
                if is_instanceof(k, VMInterrupt)
                {
                    if (k.type == token_type.k_continue)
                        continue;
                    else if (k.type == token_type.k_break)
                        break;
                    else
                        return k; // send interrupt up
                }
            }
            break;
        }
    }
}

function gmlWithStatementNode(target, blk) : gmlNode() constructor
{
	self.target = target
	self.block = blk
	
	static Fold = function ()
	{
		self.target = self.target.Fold()
		self.block = self.block.Fold();
		
		return self;
	}
	
	static Execute = function (ctx)
	{
		var target = gml_vm_expr(self.target, ctx)
        
        with target
        {
            var newctx = new gmlVMContext(ctx.script, self, ctx.scope).Extend(ctx);
            var k = gml_vm_block(other.block, newctx);
            if is_instanceof(k, VMInterrupt)
            {
                if (k.type == token_type.k_continue)
                    continue;
                else if (k.type == token_type.k_break)
                    break;
                else if (k.type == token_type.k_return)
                    return k;
            }
        }
	}
}

function gmlExprStatementNode(expr) : gmlNode() constructor
{
	self.expr = expr;
	
	if is_undefined(expr)
		throw $"Invalid expression with undefined value"
	
	static Fold = function ()
	{
		self.expr = self.expr.Fold();
		
		return self;
	}
	
	static Execute = function (ctx)
    {
        self.expr.Execute(ctx)
    }
}

function __gml_lvalue_op_minusequal(lhs, rhs, ctx) { lhs.Set(lhs.Get(ctx) - rhs, ctx); }
function __gml_lvalue_op_plusequal(lhs, rhs, ctx) { lhs.Set(lhs.Get(ctx) + rhs, ctx); }
function __gml_lvalue_op_timesequal(lhs, rhs, ctx) { lhs.Set(lhs.Get(ctx) * rhs, ctx); }
function __gml_lvalue_op_divideequal(lhs, rhs, ctx) { lhs.Set(lhs.Get(ctx) / rhs, ctx); }
function __gml_lvalue_op_orequal(lhs, rhs, ctx) { lhs.Set(lhs.Get(ctx) | rhs, ctx); }
function __gml_lvalue_op_andequal(lhs, rhs, ctx) { lhs.Set(lhs.Get(ctx) & rhs, ctx); }
function __gml_lvalue_op_xorequal(lhs, rhs, ctx) { lhs.Set(lhs.Get(ctx) ^ rhs, ctx); }
function __gml_lvalue_op_moduloequal(lhs, rhs, ctx) { lhs.Set(lhs.Get(ctx) % rhs, ctx); }

function __gml_lvalue_op_equal(lhs, rhs, ctx) { lhs.Set(rhs, ctx); }
function __gml_lvalue_op_null(lhs, rhs, ctx) { lhs.Set(lhs.Get(ctx) ?? rhs, ctx); }

function __gml_lvalue_get_op(kind)
{
	switch (kind)
	{
		case token_type.minus_equal: return __gml_lvalue_op_minusequal;
		case token_type.plus_equal: return __gml_lvalue_op_plusequal;
		case token_type.times_equal: return __gml_lvalue_op_timesequal;
		case token_type.divide_equal: return __gml_lvalue_op_divideequal;
		case token_type.or_equal: return __gml_lvalue_op_orequal;
		case token_type.and_equal: return __gml_lvalue_op_andequal;
		case token_type.xor_equal: return __gml_lvalue_op_xorequal;
		case token_type.modulo_equal: return __gml_lvalue_op_moduloequal;
		
		case token_type.equal: return __gml_lvalue_op_equal;
		case token_type.nullcoalesce_equal: return __gml_lvalue_op_null;
		
		default: throw $"__gml_lvalue_get_op unknown operator {kind}"
	}
}

function gmlLValueStatementNode(left, right, kind) : gmlNode() constructor
{
	self.left = left;
	self.right = right;
	self.kind = kind;
	
	self.func = __gml_lvalue_get_op(self.kind)
	
	static Fold = function ()
	{
		self.left = self.left.Fold();
		self.right = self.right.Fold();
		
		return self;
	}
	
	static Execute = function (ctx)
	{
		var lhs = gml_vm_expr_lvalue(self.left, ctx), rhs = gml_vm_expr(self.right, ctx);
    	
    	return self.func(lhs, rhs, ctx)
	}
}

function gmlForStatementNode(parts, blk) : gmlNode() constructor
{
	if array_length(parts) != 3
		throw "Invalid gmlForStatementNode created"
		
	self.parts = parts
	self.block = blk
	
	static Fold = function ()
	{
		for (var i = 0; i < array_length(self.parts); i++)
		{
			var p = self.parts[i];
			
			if is_array(p)
				for (var j = 0; j < array_length(p); j++)
					p[j] = p[j].Fold();
			else
				self.parts[i] = p.Fold();
		}
			
		self.block = self.block.Fold();
		
		var cond = self.parts[1]
		if is_instanceof(cond, gmlLeafNode) && !cond.data
			return new gmlNode(); // expression is guaranteed to die
		
		return self;
	}
	
	static Execute = function (ctx)
	{
		var init = self.parts[0], cond = self.parts[1], step = self.parts[2];
        
        for (__gml_vm_node(init, ctx); gml_vm_expr(cond, ctx); __gml_vm_node(step, ctx))
        {
            var k = gml_vm_block(self.block, ctx);
            if is_instanceof(k, VMInterrupt)
            {
                if (k.type == token_type.k_continue)
                    continue;
                else if (k.type == token_type.k_break)
                    break;
                else
                    return k; // up up and away
            }
        }
	}
}

function gmlRepeatStatementNode(times, blk) : gmlNode() constructor 
{
    self.times = times;
    self.block = blk;
    
    static Fold = function ()
    {
    	self.times = self.times.Fold();
    	self.block = self.block.Fold();
    	
    	if is_instanceof(self.times, gmlLeafNode) && self.times.data == 0
    		return new gmlNode();
    	
    	return self;
    }
    
    static Execute = function (ctx)
    {
    	var times = gml_vm_expr(self.times, ctx), block = self.block;
        
        repeat times
        {
            var k = gml_vm_block(block, ctx);
            if is_instanceof(k, VMInterrupt)
            {
                if (k.type == token_type.k_continue)
                    continue;
                else if (k.type == token_type.k_break)
                    break;
                else
                    return k; // up up and all the way up
            }
        }
    }
}

function gmlTryStatementNode(try_block, catch_block, catch_param_name = undefined, finally_block = undefined) : gmlNode() constructor
{
    self.try_block = try_block
    self.catch_block = catch_block
    self.catch_param_name = catch_param_name
    self.finally_block = finally_block
    
    static Fold = function ()
    {
    	self.try_block = self.try_block.Fold();
    	
    	if !is_undefined(self.catch_block)
    		self.catch_block = self.catch_block.Fold();
    		
    	return self;
    }
    
    static TryRunFinally = function (ctx)
    {
    	if !is_undefined(self.finally_block)
    		return gml_vm_block(self.finally_block, ctx)
    }
    
    static Execute = function (ctx)
    {
    	var tryblk = self.try_block, catchblk = self.catch_block, catch_parname = self.catch_param_name;
        
        try
        {
            var k = gml_vm_block(tryblk, ctx)
            if !is_undefined(k)
            	return k;
        }
        catch (err)
        {
            if !is_undefined(self.catch_block)
            {
            	if !is_undefined(catch_parname)
	                ctx.SetVar(catch_parname, err, ctx.locals)
	            
	            var k = gml_vm_block(catchblk, ctx)
	            if !is_undefined(k)
	            	return k;
            }
        }
        finally
        {
        	var k = self.TryRunFinally(ctx)
        	if !is_undefined(k) throw "Can't use break, continue, exit, return in finally."
        }
    }
}

function gmlSwitchStatementNode(compared) : gmlNode() constructor 
{
    self.compared = compared
    self.cases = []
    
    static PushCase = function (value, stmts)
    {
        array_push(self.cases, { value, stmts })
    }
    
    static Fold = function ()
    {
    	self.compared = self.compared.Fold();
    	
    	array_foreach(self.cases, function (el)
    	{
    		if el.value != 0
    			el.value = el.value.Fold();
    		
    		for (var i = 0; i < array_length(el.stmts); i++)
    			el.stmts[i] = el.stmts[i].Fold();
    	})
    	
    	if array_length(self.cases) == 0
    		return new gmlNode(); // useless switch
    	
    	return self;
    }
    
    static Execute = function (ctx)
    {
    	var compared = gml_vm_expr(self.compared, ctx), cases = self.cases;
        var target = -1, _default = -1;
        
        // search for the required case
        for (var i = 0; i < array_length(cases); i++)
        {
            var _case = cases[i], is_default = _case.value == 0
            
            // note down the default one
            if is_default
            {
            	_default = i;
            	continue;
            }
            
            var casevalue = gml_vm_expr(_case.value, ctx)
            if (casevalue == compared)
            {
                target = i;
            	break;
            }
        }
        
        var entry = target == -1 ? _default : target;
        if entry != -1
        {
        	// keep executing everything from target onwards EXCEPT if it breaks
        	for (; entry < array_length(cases); entry++)
        	{
        		var _case = cases[entry]
	        	var k = gml_vm_block(_case.stmts, ctx);
	            if is_instanceof(k, VMInterrupt)
	            {
	                if (k.type == token_type.k_break)
	                    break;
	                else
	                    return k; // uppest of the ups
	            }
        	}
        }
    }
} 

function gmlTernaryNode(condition, truthy, falsy) : gmlNode() constructor 
{
    self.cond = condition
    self.truthy = truthy
    self.falsy = falsy;
    
    static Fold = function ()
    {
    	self.cond = self.cond.Fold();
    	self.truthy = self.truthy.Fold();
    	self.falsy = self.falsy.Fold();
    	
    	if is_instanceof(self.cond, gmlLeafNode)
    	{
    		// it is decidable right now!
    		return self.cond.data ? self.truthy : self.falsy;
    	}
    	
    	return self;
    }
    
    static Execute = function (ctx)
    {
    	var cond = gml_vm_expr(self.cond, ctx)
        
        return cond ? gml_vm_expr(self.truthy, ctx) : gml_vm_expr(self.falsy, ctx)
    }
}

function gmlReturnStatementNode(node) : gmlNode() constructor 
{
    self.node = node;
    
    static Fold = function ()
    {
    	if !is_undefined(self.node)
    		self.node = self.node.Fold();
    	
    	return self;
    }
    
    static Execute = function (ctx)
    {
    	var code = is_undefined(self.node) ? self.node : gml_vm_expr(self.node, ctx);
        return new VMInterrupt(token_type.k_return, code)
    }
}

function gmlInterruptStatementNode(type) : gmlNode() constructor 
{
    self.type = type
    
    static Execute = function (ctx)
    {
    	return new VMInterrupt(self.type)
    }
}
function gmlThrowStatementNode(message) : gmlNode() constructor 
{
    self.message = message;
    
    static Execute = function (ctx)
    {
    	var msg = gml_vm_expr(self.message, ctx)
        
        throw msg;
    }
}
#endregion

__gml.last_tokenpos = undefined

function gml_consume(tokens)
{
    var tok = tokens.Consume();
    __gml.last_tokenpos = tok[2];
    return tok;
}

function gml_parse_match(tokens, tok, quiet = false)
{
	if !is_array(tok)
		tok = [tok]
	if !array_contains(tok, tokens.next_token[0])
	{
		if quiet
			return;
        
        for (var i = 0; i < array_length(tok); i++)
            tok[i] = gml_token_name(tok[i])
		throw $"Expected {tok} but got {gml_token_name(tokens.next_token[0])}"
	}
	
	return gml_consume(tokens);
}
function gml_parse_try_eat(tokens, tok)
{
    if !is_array(tok)
        tok = [tok]
    
    if gml_eof(tokens)
        return;
    
    if array_contains(tok, tokens.next_token[0])
    {
        gml_consume(tokens)
    }
}

function gml_parse_expr_leaf_node_primary(tokens)
{
	// number
	if tokens.next_token[0] == token_type.minus || tokens.next_token[0] == token_type.plus
	{
		var s = gml_consume(tokens)[0] == token_type.plus ? 1 : -1; // consume +/-
		var n = gml_parse_expr_leaf_node(tokens); // consume num and drop
		return new gmlOpNode(token_type.multiply, n, new gmlLeafNode(s))
	}
	if tokens.next_token[0] == token_type.number
	{
		var n = gml_consume(tokens)[1]; // consume num and drop
		return new gmlLeafNode(n);
	}
	
	// string
	if tokens.next_token[0] == token_type.text
	{
		var s = gml_consume(tokens)[1];
		return new gmlLeafNode(s);
	}
	
	// array
	if tokens.next_token[0] == token_type.open_bracket
	{
		var contents = []
		gml_consume(tokens); // consume [
		while tokens.next_token[0] != token_type.close_bracket
		{
			var s = gml_parse_expr_ops(tokens)
			if tokens.next_token[0] != token_type.comma && tokens.next_token[0] != token_type.close_bracket
				throw "Invalid array syntax (expected a comma or a closing bracket for array end)"
			else if tokens.next_token[0] != token_type.close_bracket
				gml_consume(tokens); // consume ,
				
			array_push(contents, s);
		}
		
		gml_consume(tokens); // consume ]
		return new gmlArrayNode(contents) 
	}
	
    // struct
    if tokens.next_token[0] == token_type.open_brace
    {
        var struct = {}
        gml_consume(tokens) // {
        
        while tokens.next_token[0] != token_type.close_brace
        {
            var key;
            
            // parse key
            if tokens.next_token[0] == token_type.symbol
                key = gml_parse_match(tokens, token_type.symbol)[1];
            else
                key = gml_parse_match(tokens, token_type.text)[1];
            
            var value;
            
            if tokens.next_token[0] == token_type.colon
            {
                gml_parse_match(tokens, token_type.colon) // :
                value = gml_parse_expr_ops(tokens)
            }
            else 
            	value = new gmlVarNode(key);
            
            if tokens.next_token[0] == token_type.comma
            {
                gml_parse_match(tokens, token_type.comma)
            }
            else if tokens.next_token[0] != token_type.close_brace 
            {
            	throw "Expected comma in kvp list"
            }
            
            struct[$ key] = value;
        }
        
        gml_parse_match(tokens, token_type.close_brace)
        
        return new gmlStructNode(struct)
    }
    
	// symbol
	if tokens.next_token[0] == token_type.symbol
	{
		var name = gml_parse_match(tokens, token_type.symbol)[1];
		
		if __gml_vm_greenvar_has(name)
		{
			var root = new gmlGreenVarNode(name);
			
			if tokens.next_token[0] == token_type.open_bracket && !gml_is_acessortoken(tokens.next_next_token[0])
			{
				gml_consume(tokens); // [
				var index = gml_parse_expr_ops(tokens)
				gml_parse_match(tokens, token_type.close_bracket) // ]
				
				root = new gmlGreenVarIndexNode(root.data, index)
			}
			
			return root;
		}
		
		return new gmlVarNode(name);
	}
	
	// functions
	if tokens.next_token[0] == token_type.func
	{
		gml_consume(tokens); // consume func
        
        var name = "";
        if tokens.next_token[0] == token_type.symbol
        {
            name = gml_consume(tokens)[1];
        }
        
		gml_parse_match(tokens, token_type.open_paren);
		
		var arg_names = []
		var arg_optionals = {}
        
		while tokens.next_token[0] != token_type.close_paren
		{
			var symb = gml_parse_match(tokens, token_type.symbol)[1]
			array_push(arg_names, symb)
            
            if tokens.next_token[0] == token_type.equal
            {
                gml_consume(tokens); // =
                var expr = gml_parse_expr_ops(tokens)
                arg_optionals[$ symb] = expr;
            }
			
			gml_parse_match(tokens, token_type.comma, true)
		}
		gml_parse_match(tokens, token_type.close_paren)
        
        // inheritance
        var inherit_call = undefined;
        
        if tokens.next_token[0] == token_type.colon
        {
            gml_consume(tokens);
            inherit_call = gml_parse_expr_leaf_node(tokens)
            
            if !is_instanceof(inherit_call, gmlCallNode)
                throw "Can't inherit this!"
                
            inherit_call.is_new = true;
        }
		
        var is_construct = false;
        
        if tokens.next_token[0] == token_type.k_constructor
        {
            gml_consume(tokens); // constructor
            is_construct = true;
        }
        
        if !is_construct && !is_undefined(inherit_call)
            throw "Can't inherit on a non-constructor function"
        
		// keep track of what functions are visible and where
        __gml.gml_scopedepth ++ 
		var blk = gml_parse_block(tokens);
		__gml.gml_scopedepth --;
		
		var node = new gmlFunctionNode(name, arg_names, blk, is_construct, inherit_call, arg_optionals)
		
		// add it to the list of functions to be preinited so they can be reached before declaration
		if (string_length(name) > 0 && __gml.gml_scopedepth == 0)
			array_push(__gml.gml_functions, node);
			
		return node;
	}
	
	// paren
	if tokens.next_token[0]	== token_type.open_paren
	{
		gml_consume(tokens)
		var s = gml_parse_expr_ops(tokens)
		if gml_consume(tokens)[0] != token_type.close_paren
			throw "Open parenthesis must be closed."
			
		return s;
	}
}

function gml_parse_expr_leaf_incr(tokens)
{
    if is(tokens.next_token[0], token_type.increment, token_type.decrement)
    {
        var value = gml_consume(tokens)[0] == token_type.decrement ? 2 : 4;
        return value;
    }
    
    return false;
}

#region parsing leaf stages

function gml_is_acessortoken(tok)
{
	switch (tok)
    {
    case token_type.qmark: // ?
    case token_type.v_or: // |
    case token_type.dollar: // $
    case token_type.at: // @
    case token_type.hash: // #
    	return true;
    }
    
    return false;
}

// stage 1 - parse member accesses like a.b[0][1].c
function gml_parse_expr_leaf_node_is_member(token)
{
	return is(token, token_type.dot, token_type.open_bracket)
}
function gml_parse_expr_leaf_node_member(primary, tokens)
{
    while gml_parse_expr_leaf_node_is_member(tokens.next_token[0])
    {
        var toktype = gml_consume(tokens)[0];
        var type = toktype;
        var index = 0;
        
        if (toktype == token_type.dot)
        {
            index = gml_parse_match(tokens, token_type.symbol)[1];
        }
        else if (toktype == token_type.open_bracket) 
        {
            // weird accessing things
            if gml_is_acessortoken(tokens.next_token[0])
                type = gml_consume(tokens)[0];
            
        	index = [gml_parse_expr_ops(tokens)];
            
            // 2d array accessing
            if (tokens.next_token[0] == token_type.comma)
            {
            	gml_parse_match(tokens, token_type.comma) // ,
                index[1] = gml_parse_expr_ops(tokens);
            }
            
            gml_parse_match(tokens, token_type.close_bracket) // ]
        }
        
        primary = new gmlAccessNode(primary, index, type)
    }
    
	return primary;
}

// stage 2 - parse calls like a.b()
function gml_parse_expr_leaf_node_call(mb_node, tokens)
{
	while tokens.next_token[0] == token_type.open_paren
	{
	    gml_consume(tokens); // (
		
		var pars = []
		while tokens.next_token[0] != token_type.close_paren && !gml_eof(tokens)
		{
			var s = gml_parse_expr_ops(tokens)
			array_push(pars, s);
			
			gml_parse_match(tokens, token_type.comma, true);
		}
		gml_parse_match(tokens, token_type.close_paren);
		
		mb_node = new gmlCallNode(mb_node, pars);
	}
	
	return mb_node;
}

// combined stage to continuously parse the stages 1 and 2
// handles stuff like a[1]()
function gml_parse_expr_leaf_node_postfixes(tokens, node = undefined)
{
	// enum handling happens first
    if tokens.next_token[0] == token_type.symbol
    {
        var enumname = tokens.next_token[1]
        if gml_has_enum(enumname)
        {
            gml_parse_match(tokens, token_type.symbol)
            gml_parse_match(tokens, token_type.dot)
            var enumval = gml_parse_match(tokens, token_type.symbol)[1]
            
            return new gmlLeafNode(gml_get_enum(enumname, enumval))
        }
    }
    
    // combined
	node ??= gml_parse_expr_leaf_node_primary(tokens)
	
	while (true)
	{
		var next_tok = tokens.next_token[0]
		
		if gml_parse_expr_leaf_node_is_member(next_tok)
			node = gml_parse_expr_leaf_node_member(node, tokens)
		else if next_tok == token_type.open_paren
			node = gml_parse_expr_leaf_node_call(node, tokens)
		else
			break;
	}
	
	return node;
}

// stage 3 - parse modifiers like new a.b[9]()
// this links back to the postfixes stage above to handle stuff like new a().b
function gml_parse_expr_leaf_node_modifiers(tokens)
{
	if tokens.next_token[0] == token_type.k_new
	{
		gml_consume(tokens); // new
		
		// handle the call ourselves now
		var primary = gml_parse_expr_leaf_node_primary(tokens)
		while gml_parse_expr_leaf_node_is_member(tokens.next_token[0])
			primary = gml_parse_expr_leaf_node_postfixes(tokens, primary) // only parse up to the desired levels
			
		var callnode = gml_parse_expr_leaf_node_call(primary, tokens)
		
		callnode.is_new = true;
		return gml_parse_expr_leaf_node_postfixes(tokens, callnode); // LINK BACK to earlier stages that loop
	}
	
	return gml_parse_expr_leaf_node_postfixes(tokens);
}

// stage 4 - parse unary like ++a or ~n
// no linking back, this is the last stage
function gml_parse_expr_leaf_node_unary(tokens)
{
	while tokens.next_token[0] == token_type.negate
	{
	    gml_consume(tokens) // !
	    var n = gml_parse_expr_leaf_node_unary(tokens)
	    return new gmlNegateNode(n);
	}
	
	while tokens.next_token[0] == token_type.v_negate
	{
	    gml_consume(tokens) // ~
	    var n = gml_parse_expr_leaf_node_unary(tokens)
	    return new gmlBitNegateNode(n);
	}
	
	var leafincr = gml_parse_expr_leaf_incr(tokens)
	if leafincr
	{
	    var n = gml_parse_expr_leaf_node_unary(tokens)
	    return new gmlIncrementNode(n, true, leafincr - 3)
	}

	var core = gml_parse_expr_leaf_node_modifiers(tokens)
	
	var leafincr = gml_parse_expr_leaf_incr(tokens)
	if leafincr
	{
	    core = new gmlIncrementNode(core, false, leafincr - 3)
	}
	
	return core;
}

function gml_parse_expr_leaf_node(tokens)
{
	return gml_parse_expr_leaf_node_unary(tokens);
}

#endregion

function gml_parse_expr_ops(tokens, odepth = undefined)
{
    // from least to most
	static depths = [
    undefined, 
    
    token_type.v_and, 
    token_type.v_or, 
    token_type.v_xor, 
    token_type.bit_lshift, 
    token_type.bit_rshift, 
    
    token_type.divide, 
    token_type.modulo, 
    token_type.multiply,
    token_type.minus, 
    token_type.plus,
    
    token_type.nullcoalesce,
    
    token_type.b_equal, 
    token_type.b_nequal, 
    token_type.b_biggereq, 
    token_type.b_lesseq, 
    token_type.biggerthan, 
    token_type.lessthan,
    
    token_type.b_and, 
    token_type.b_or, 
    
    token_type.qmark, 
    
    token_type.equal, // interpreted as ==
    /*token_type.plus_equal, 
    token_type.minus_equal, 
    token_type.times_equal, 
    token_type.divide_equal, */
    ]
    
    if is_undefined(odepth)
        odepth = array_length(depths) - 1
    
	var tmatch = depths[odepth]
	
	if tmatch == undefined
	{
		// parse leaf
		return gml_parse_expr_leaf_node(tokens)
	}
    
	var root = gml_parse_expr_ops(tokens, odepth - 1)
    
	if gml_eof(tokens) || tokens.next_token[0] == token_type.semicolon
		return root
    
    if is_undefined(root)
    {
        throw $"Invalid left hand side term"
    }
    
	while tokens.next_token[0] == tmatch
	{
		gml_consume(tokens) // consume op
        
        var rhs = gml_parse_expr_ops(tokens, odepth - 1);
        
        if tmatch == token_type.qmark
        {
            gml_parse_match(tokens, token_type.colon)
            
            var falsy = gml_parse_expr_ops(tokens, odepth - 1)
            
            root = new gmlTernaryNode(root, rhs, falsy);
        }
		else 
            root = new gmlOpNode(tmatch, root, rhs) 
		
		if gml_eof(tokens)
			return root
	}
	
	return root;
}

// code parser
function gmlBlockNode(statements) : gmlNode() constructor
{
	self.statements = statements
	
	static Fold = function ()
	{
		for (var i = 0; i < array_length(self.statements); i++)
			self.statements[i] = self.statements[i].Fold();
			
		return self;
	}
}

function gml_parse_block(tokens, top = false)
{
	if !top
	{
		if tokens.next_token[0] != token_type.open_brace
		{
			// only parse 1 statement
			var s = gml_parse_statement(tokens);
	        gml_parse_try_eat(tokens, token_type.semicolon)
	        
	        return new gmlBlockNode(is_array(s) ? s : [s]);
		}
	    
	    gml_consume(tokens); // consume {
	}

	var stat = []
	
	while (!top && tokens.next_token[0] != token_type.close_brace) || (top && tokens.next_token[0] != token_type.eof)
	{
        var s = gml_parse_statement(tokens);
        
        if is_array(s)
        {
        	for (var i = 0; i < array_length(s); i++)
        	{
        		var st = s[i]
        		// hoist statics to the top
        		if is_instanceof(st, gmlVarStatementNode) && st.type == token_type.k_static
        		{
        			array_delete(s, i, 1)
        			i--; // realign
        			array_insert(stat, 0, st)
        		}
        	}
        }
    	array_extend(stat, s)
        	
        gml_parse_try_eat(tokens, token_type.semicolon)
	}
    
    if !top
		gml_parse_match(tokens, token_type.close_brace)
	
	return new gmlBlockNode(stat);
}

function gml_eof(tokens)
{
    return tokens.Depleted() || tokens.next_token[0] == token_type.eof;
}

#region enum managing
function gml_add_enum(enum_name, name, value)
{
    if !struct_exists(__gml.gml_enums, enum_name)
        __gml.gml_enums[$ enum_name] = {}
    
    __gml.gml_enums[$ enum_name][$ name] = value;
}

function gml_has_enum(enum_name)
{
    return struct_exists(__gml.gml_enums, enum_name)
}

function gml_get_enum(enum_name, name)
{
    return __gml.gml_enums[$ enum_name][$ name]
}
#endregion

function gml_parse_statement(tokens)
{
    if tokens.next_token[0] == token_type.semicolon
    {
        return [];
    }
    
	var tok = tokens.next_token
	switch tok[0]
	{
	case token_type.k_if:
	case token_type.k_while:
		gml_consume(tokens)
		
		var e = gml_parse_expr_ops(tokens)
		
		gml_parse_try_eat(tokens, token_type.k_then)
		
		var blk = gml_parse_block(tokens)
        
        var elsepart = undefined
        
        if tokens.next_token[0] == token_type.k_else
        {
            if (tok[0] != token_type.k_if)
                throw "Else can only follow an if";
            
            gml_consume(tokens); // else
            elsepart = gml_parse_block(tokens)
        }
		
		return new gmlConditionalStatementNode(e, blk, tok[0], elsepart)
        
    case token_type.k_with:
        gml_consume(tokens);
        
        var target = gml_parse_expr_ops(tokens)
        var blk = gml_parse_block(tokens)
        
        return new gmlWithStatementNode(target, blk)
		
    case token_type.k_do:
        gml_consume(tokens)
        var blk = gml_parse_block(tokens)
        
        gml_parse_match(tokens, token_type.k_until)
        var cond = gml_parse_expr_ops(tokens)
        
        return new gmlDoUntilStatementNode(cond, blk)
        
	case token_type.k_for:
		gml_consume(tokens)
		
		gml_parse_match(tokens, token_type.open_paren)
		
		// parse all 3 expressions
		var parts = []
        
        parts[0] = gml_parse_statement(tokens)
        gml_parse_match(tokens, token_type.semicolon);
        
        parts[1] = gml_parse_expr_ops(tokens)
        gml_parse_match(tokens, token_type.semicolon);
        
        parts[2] = gml_parse_statement(tokens)
		
        gml_parse_match(tokens, token_type.close_paren)
        
		var blk = gml_parse_block(tokens)
		return new gmlForStatementNode(parts, blk)
        
    case token_type.k_throw:
        gml_consume(tokens)
        
        var message = gml_parse_expr_ops(tokens)
        
        return new gmlThrowStatementNode(message)
        
    case token_type.k_try:
        gml_consume(tokens)
        
        var tryblk = gml_parse_block(tokens);
        var catchblk = undefined, finallyblk = undefined;
        var catchparam = undefined
        
        if tokens.next_token[0] == token_type.k_catch
        {
            gml_consume(tokens) // catch
            
            if tokens.next_token[0] == token_type.open_paren
            {
                gml_consume(tokens) // (
                catchparam = gml_parse_match(tokens, token_type.symbol)[1]
                gml_parse_match(tokens, token_type.close_paren)
            }
            
            catchblk = gml_parse_block(tokens)
        }
        
        if tokens.next_token[0] == token_type.k_finally
        {
            gml_consume(tokens) // finally
            
            finallyblk = gml_parse_block(tokens)
        }
        
        return new gmlTryStatementNode(tryblk, catchblk, catchparam, finallyblk)
        
    case token_type.k_repeat:
        gml_consume(tokens)
        
        var times = gml_parse_expr_ops(tokens)
        var blk = gml_parse_block(tokens)
        
        return new gmlRepeatStatementNode(times, blk);
        
    case token_type.k_return:
        gml_consume(tokens);
        
        return new gmlReturnStatementNode(gml_parse_expr_ops(tokens))
        
    case token_type.k_exit:
        gml_consume(tokens);
        
        return new gmlReturnStatementNode(undefined)
        
    case token_type.k_break:
    case token_type.k_continue:
        return new gmlInterruptStatementNode(gml_consume(tokens)[0])
        
    case token_type.k_var:
    case token_type.k_static:
    case token_type.k_globalvar:
        gml_consume(tokens)
        
        var stmts = [];
        
        do
        {
            if array_length(stmts) > 0
                gml_parse_match(tokens, token_type.comma)
            
            var name = gml_parse_match(tokens, token_type.symbol)[1]; // name
            var value = undefined;
            
            if (tokens.next_token[0] == token_type.equal)
            {
                gml_parse_match(tokens, token_type.equal) // =
                value = gml_parse_expr_ops(tokens) // expr
            }
            
            var node = new gmlVarStatementNode(name, value, tok[0]);
            
            array_push(stmts, node);
        } until (tokens.next_token[0] != token_type.comma)
        
        return stmts;
        
    case token_type.k_enum:
        gml_consume(tokens);
        
        var wholename = gml_parse_match(tokens, token_type.symbol)[1];
        gml_parse_match(tokens, token_type.open_brace)
        
        var count = 0;
        
        while tokens.next_token[0] != token_type.close_brace
        {
            var valuename = gml_parse_match(tokens, token_type.symbol)[1];
            
            if tokens.next_token[0] == token_type.equal
            {
                gml_parse_match(tokens, token_type.equal);
                count = gml_parse_match(tokens, token_type.number)[1];
            }
            
            gml_add_enum(wholename, valuename, count++)
            
            if tokens.next_token[0] == token_type.comma
                gml_parse_match(tokens, token_type.comma); // ,
            else if tokens.next_token[0] != token_type.close_brace
            	throw $"Unexpected token in enum definition: {gml_token_name(tokens.next_token[0])}"
        }
        gml_parse_match(tokens, token_type.close_brace) // }
        return [];
        
    case token_type.k_switch:
        gml_consume(tokens)
        
        var compared = gml_parse_expr_ops(tokens)
        
        gml_parse_match(tokens, token_type.open_brace) // {
        
        var node = new gmlSwitchStatementNode(compared)
        
        while tokens.next_token[0] != token_type.close_brace
        {
            var case_value = 0
            
            if tokens.next_token[0] == token_type.k_default
            {
                gml_consume(tokens) // default
            }
            else 
            {
                gml_parse_match(tokens, token_type.k_case) // case
                case_value = gml_parse_expr_ops(tokens)
            }
            
            gml_parse_match(tokens, token_type.colon) // :
            
            var case_statements = []
            
            while !is(tokens.next_token[0], token_type.close_brace, token_type.k_case, token_type.k_default)
            {
                var stmt = gml_parse_statement(tokens)
                gml_parse_try_eat(tokens, token_type.semicolon)
                
                array_extend(case_statements, stmt)
            }
            node.PushCase(case_value, case_statements)
        }
        
        gml_parse_match(tokens, token_type.close_brace)
        return node;
		
    case token_type.k_delete:
        gml_consume(tokens) // delete
        var leaf = gml_parse_expr_leaf_node(tokens);
        return new gmlLValueStatementNode(leaf, new gmlLeafNode(undefined), token_type.equal);
        
	default:
		var possible_left = gml_parse_expr_leaf_node(tokens);
		var is_lvalue = is(tokens.next_token[0], token_type.plus_equal, token_type.equal, token_type.minus_equal, token_type.times_equal, token_type.divide_equal, token_type.nullcoalesce_equal, token_type.and_equal, token_type.or_equal, token_type.xor_equal, token_type.modulo_equal)
		
		if is_lvalue
		{
			var lvtok = gml_consume(tokens) // = or sth
			return new gmlLValueStatementNode(possible_left, gml_parse_expr_ops(tokens), lvtok[0]);
		}
		
		return new gmlExprStatementNode(possible_left);
	}
}

#region VM

#region cache assets
function gml_vm_cache_assettype(scr_name, scr_exists, i = 0)
{
	for (; scr_exists(i); i++)
	{
		var name = scr_name(i);
		if !string_starts_with(name, "@@")
			__gml.vm_cached_assets[$ name] = i;
	}
}

function __gml_init_assets()
{
	__gml.vm_cached_assets = {}
	
	gml_vm_cache_assettype(script_get_name, function (i)
	{
		return script_get_name(i) != "<undefined>"
	})
	gml_vm_cache_assettype(script_get_name, script_exists, 100000)
	gml_vm_cache_assettype(sprite_get_name, sprite_exists)
	gml_vm_cache_assettype(object_get_name, object_exists)
	gml_vm_cache_assettype(room_get_name, room_exists)
	gml_vm_cache_assettype(tileset_get_name, function (i)
	{
		return tileset_get_name(i) != "<undefined>"
	})
}
#endregion

#region green var
function __gml_vm_greenvar(bname, bfunc, is_arr = false)
{
	__gml.vm_greenvars[$ bname] = {
		bfunc,
		is_arr
	};
}

// makes sure to call them in the correct scope
function __gml_vm_greenvar_resolve(fn, ctx, set, v = 0, ind = 0)
{
	fn = method(ctx.scope, fn)
	
	with ctx.scope_other
		return fn(set, v, ind)
}

// these nodes also act as runtime instances for greenvar resolution
function gmlGreenVarNode(bname) : gmlNode() constructor
{
	self.data = __gml_vm_greenvar_get(bname)
	
	static Set = function (v, ctx)
	{
		return __gml_vm_greenvar_resolve(self.data.bfunc, ctx, true, v)
	}
	
	static Get = function (ctx)
	{
		if self.data.is_arr
			throw "This special variable is an array and can only be indexed";
			
		return __gml_vm_greenvar_resolve(self.data.bfunc, ctx, false)
	}
	
	static Execute = function (ctx)
	{
		return self; // refeed it back into the expr middleman functions
	}
}
function gmlGreenVarIndexNode(gv_data, bindex) : gmlNode() constructor
{
	self.data = gv_data
	self.bindex = bindex;
	self.bindex_v = undefined;
	
	static Set = function (v, ctx)
	{
		if !self.data.is_arr
			throw "Cannot set at an index a non-array special variable";
			
		self.bindex_v ??= gml_vm_expr(self.bindex, ctx);
		return __gml_vm_greenvar_resolve(self.data.bfunc, ctx, true, v, self.bindex_v)
	}
	
	static Get = function (ctx)
	{
		if !self.data.is_arr
			throw "Cannot index a non-array special variable";
			
		self.bindex_v ??= gml_vm_expr(self.bindex, ctx);
		return __gml_vm_greenvar_resolve(self.data.bfunc, ctx, false, 0, self.bindex_v)
	}
}

function __gml_vm_greenvar_has(bname)
{
	return struct_exists(__gml.vm_greenvars, bname);
}
function __gml_vm_greenvar_get(bname)
{
	if !__gml_vm_greenvar_has(bname)
		return;
	
	return __gml.vm_greenvars[$ bname];
}

// pulled from GmlSpec
function __gml_init_greenvar()
{
	__gml.vm_greenvars = {}
	
	__gml_vm_greenvar("font_texture_page_size", function (_set, _v, _ind)
	{
	  if (_set) font_texture_page_size = _v;
	  return font_texture_page_size;
	});
	__gml_vm_greenvar("instance_count", function (_set, _v, _ind)
	{
	  return instance_count;
	});
	__gml_vm_greenvar("instance_id", function (_set, _v, _ind)
	{
	  return instance_id[_ind];
	}, true);
	__gml_vm_greenvar("alarm", function (_set, _v, _ind)
	{
	  if (_set) alarm[_ind] = _v;
	  return alarm[_ind];
	}, true);
	__gml_vm_greenvar("depth", function (_set, _v, _ind)
	{
	  if (_set) depth = _v;
	  return depth;
	});
	__gml_vm_greenvar("direction", function (_set, _v, _ind)
	{
	  if (_set) direction = _v;
	  return direction;
	});
	__gml_vm_greenvar("friction", function (_set, _v, _ind)
	{
	  if (_set) friction = _v;
	  return friction;
	});
	__gml_vm_greenvar("gravity", function (_set, _v, _ind)
	{
	  if (_set) gravity = _v;
	  return gravity;
	});
	__gml_vm_greenvar("gravity_direction", function (_set, _v, _ind)
	{
	  if (_set) gravity_direction = _v;
	  return gravity_direction;
	});
	__gml_vm_greenvar("hspeed", function (_set, _v, _ind)
	{
	  if (_set) hspeed = _v;
	  return hspeed;
	});
	__gml_vm_greenvar("id", function (_set, _v, _ind)
	{
	  return id;
	});
	__gml_vm_greenvar("layer", function (_set, _v, _ind)
	{
	  if (_set) layer = _v;
	  return layer;
	});
	__gml_vm_greenvar("on_ui_layer", function (_set, _v, _ind)
	{
	  return on_ui_layer;
	});
	__gml_vm_greenvar("persistent", function (_set, _v, _ind)
	{
	  if (_set) persistent = _v;
	  return persistent;
	});
	__gml_vm_greenvar("solid", function (_set, _v, _ind)
	{
	  if (_set) solid = _v;
	  return solid;
	});
	__gml_vm_greenvar("speed", function (_set, _v, _ind)
	{
	  if (_set) speed = _v;
	  return speed;
	});
	__gml_vm_greenvar("visible", function (_set, _v, _ind)
	{
	  if (_set) visible = _v;
	  return visible;
	});
	__gml_vm_greenvar("managed", function (_set, _v, _ind)
	{
	  return managed;
	});
	__gml_vm_greenvar("vspeed", function (_set, _v, _ind)
	{
	  if (_set) vspeed = _v;
	  return vspeed;
	});
	__gml_vm_greenvar("x", function (_set, _v, _ind)
	{
	  if (_set) x = _v;
	  return x;
	});
	__gml_vm_greenvar("xprevious", function (_set, _v, _ind)
	{
	  if (_set) xprevious = _v;
	  return xprevious;
	});
	__gml_vm_greenvar("xstart", function (_set, _v, _ind)
	{
	  if (_set) xstart = _v;
	  return xstart;
	});
	__gml_vm_greenvar("y", function (_set, _v, _ind)
	{
	  if (_set) y = _v;
	  return y;
	});
	__gml_vm_greenvar("yprevious", function (_set, _v, _ind)
	{
	  if (_set) yprevious = _v;
	  return yprevious;
	});
	__gml_vm_greenvar("ystart", function (_set, _v, _ind)
	{
	  if (_set) ystart = _v;
	  return ystart;
	});
	__gml_vm_greenvar("object_index", function (_set, _v, _ind)
	{
	  return object_index;
	});
	__gml_vm_greenvar("event_number", function (_set, _v, _ind)
	{
	  return event_number;
	});
	__gml_vm_greenvar("event_object", function (_set, _v, _ind)
	{
	  return event_object;
	});
	__gml_vm_greenvar("event_type", function (_set, _v, _ind)
	{
	  return event_type;
	});
	__gml_vm_greenvar("path_endaction", function (_set, _v, _ind)
	{
	  if (_set) path_endaction = _v;
	  return path_endaction;
	});
	__gml_vm_greenvar("path_index", function (_set, _v, _ind)
	{
	  return path_index;
	});
	__gml_vm_greenvar("path_orientation", function (_set, _v, _ind)
	{
	  if (_set) path_orientation = _v;
	  return path_orientation;
	});
	__gml_vm_greenvar("path_position", function (_set, _v, _ind)
	{
	  if (_set) path_position = _v;
	  return path_position;
	});
	__gml_vm_greenvar("path_positionprevious", function (_set, _v, _ind)
	{
	  if (_set) path_positionprevious = _v;
	  return path_positionprevious;
	});
	__gml_vm_greenvar("path_scale", function (_set, _v, _ind)
	{
	  if (_set) path_scale = _v;
	  return path_scale;
	});
	__gml_vm_greenvar("path_speed", function (_set, _v, _ind)
	{
	  if (_set) path_speed = _v;
	  return path_speed;
	});
	__gml_vm_greenvar("room", function (_set, _v, _ind)
	{
	  if (_set) room = _v;
	  return room;
	});
	__gml_vm_greenvar("room_first", function (_set, _v, _ind)
	{
	  return room_first;
	});
	__gml_vm_greenvar("room_height", function (_set, _v, _ind)
	{
	  if (_set) room_height = _v;
	  return room_height;
	});
	__gml_vm_greenvar("room_last", function (_set, _v, _ind)
	{
	  return room_last;
	});
	__gml_vm_greenvar("room_persistent", function (_set, _v, _ind)
	{
	  if (_set) room_persistent = _v;
	  return room_persistent;
	});
	__gml_vm_greenvar("room_width", function (_set, _v, _ind)
	{
	  if (_set) room_width = _v;
	  return room_width;
	});
	__gml_vm_greenvar("in_sequence", function (_set, _v, _ind)
	{
	  if (_set) in_sequence = _v;
	  return in_sequence;
	});
	__gml_vm_greenvar("sequence_instance", function (_set, _v, _ind)
	{
	  return sequence_instance;
	});
	__gml_vm_greenvar("drawn_by_sequence", function (_set, _v, _ind)
	{
	  if (_set) drawn_by_sequence = _v;
	  return drawn_by_sequence;
	});
	__gml_vm_greenvar("bbox_bottom", function (_set, _v, _ind)
	{
	  return bbox_bottom;
	});
	__gml_vm_greenvar("bbox_left", function (_set, _v, _ind)
	{
	  return bbox_left;
	});
	__gml_vm_greenvar("bbox_right", function (_set, _v, _ind)
	{
	  return bbox_right;
	});
	__gml_vm_greenvar("bbox_top", function (_set, _v, _ind)
	{
	  return bbox_top;
	});
	__gml_vm_greenvar("image_alpha", function (_set, _v, _ind)
	{
	  if (_set) image_alpha = _v;
	  return image_alpha;
	});
	__gml_vm_greenvar("image_angle", function (_set, _v, _ind)
	{
	  if (_set) image_angle = _v;
	  return image_angle;
	});
	__gml_vm_greenvar("image_blend", function (_set, _v, _ind)
	{
	  if (_set) image_blend = _v;
	  return image_blend;
	});
	__gml_vm_greenvar("image_index", function (_set, _v, _ind)
	{
	  if (_set) image_index = _v;
	  return image_index;
	});
	__gml_vm_greenvar("image_number", function (_set, _v, _ind)
	{
	  return image_number;
	});
	__gml_vm_greenvar("image_speed", function (_set, _v, _ind)
	{
	  if (_set) image_speed = _v;
	  return image_speed;
	});
	__gml_vm_greenvar("image_xscale", function (_set, _v, _ind)
	{
	  if (_set) image_xscale = _v;
	  return image_xscale;
	});
	__gml_vm_greenvar("image_yscale", function (_set, _v, _ind)
	{
	  if (_set) image_yscale = _v;
	  return image_yscale;
	});
	__gml_vm_greenvar("mask_index", function (_set, _v, _ind)
	{
	  if (_set) mask_index = _v;
	  return mask_index;
	});
	__gml_vm_greenvar("sprite_height", function (_set, _v, _ind)
	{
	  return sprite_height;
	});
	__gml_vm_greenvar("sprite_index", function (_set, _v, _ind)
	{
	  if (_set) sprite_index = _v;
	  return sprite_index;
	});
	__gml_vm_greenvar("sprite_width", function (_set, _v, _ind)
	{
	  return sprite_width;
	});
	__gml_vm_greenvar("sprite_xoffset", function (_set, _v, _ind)
	{
	  return sprite_xoffset;
	});
	__gml_vm_greenvar("sprite_yoffset", function (_set, _v, _ind)
	{
	  return sprite_yoffset;
	});
	__gml_vm_greenvar("timeline_index", function (_set, _v, _ind)
	{
	  if (_set) timeline_index = _v;
	  return timeline_index;
	});
	__gml_vm_greenvar("timeline_loop", function (_set, _v, _ind)
	{
	  if (_set) timeline_loop = _v;
	  return timeline_loop;
	});
	__gml_vm_greenvar("timeline_position", function (_set, _v, _ind)
	{
	  if (_set) timeline_position = _v;
	  return timeline_position;
	});
	__gml_vm_greenvar("timeline_running", function (_set, _v, _ind)
	{
	  if (_set) timeline_running = _v;
	  return timeline_running;
	});
	__gml_vm_greenvar("timeline_speed", function (_set, _v, _ind)
	{
	  if (_set) timeline_speed = _v;
	  return timeline_speed;
	});
	__gml_vm_greenvar("view_camera", function (_set, _v, _ind)
	{
	  if (_set) view_camera[_ind] = _v;
	  return view_camera[_ind];
	}, true);
	__gml_vm_greenvar("view_current", function (_set, _v, _ind)
	{
	  return view_current;
	});
	__gml_vm_greenvar("view_enabled", function (_set, _v, _ind)
	{
	  if (_set) view_enabled = _v;
	  return view_enabled;
	});
	__gml_vm_greenvar("view_hport", function (_set, _v, _ind)
	{
	  if (_set) view_hport[_ind] = _v;
	  return view_hport[_ind];
	}, true);
	__gml_vm_greenvar("view_surface_id", function (_set, _v, _ind)
	{
	  if (_set) view_surface_id[_ind] = _v;
	  return view_surface_id[_ind];
	}, true);
	__gml_vm_greenvar("view_visible", function (_set, _v, _ind)
	{
	  if (_set) view_visible[_ind] = _v;
	  return view_visible[_ind];
	}, true);
	__gml_vm_greenvar("view_wport", function (_set, _v, _ind)
	{
	  if (_set) view_wport[_ind] = _v;
	  return view_wport[_ind];
	}, true);
	__gml_vm_greenvar("view_xport", function (_set, _v, _ind)
	{
	  if (_set) view_xport[_ind] = _v;
	  return view_xport[_ind];
	}, true);
	__gml_vm_greenvar("view_yport", function (_set, _v, _ind)
	{
	  if (_set) view_yport[_ind] = _v;
	  return view_yport[_ind];
	}, true);
	__gml_vm_greenvar("debug_mode", function (_set, _v, _ind)
	{
	  return debug_mode;
	});
	__gml_vm_greenvar("fps", function (_set, _v, _ind)
	{
	  return fps;
	});
	__gml_vm_greenvar("fps_real", function (_set, _v, _ind)
	{
	  return fps_real;
	});
	__gml_vm_greenvar("application_surface", function (_set, _v, _ind)
	{
	  return application_surface;
	});
	__gml_vm_greenvar("program_directory", function (_set, _v, _ind)
	{
	  return program_directory;
	});
	__gml_vm_greenvar("temp_directory", function (_set, _v, _ind)
	{
	  return temp_directory;
	});
	__gml_vm_greenvar("cache_directory", function (_set, _v, _ind)
	{
	  return cache_directory;
	});
	__gml_vm_greenvar("working_directory", function (_set, _v, _ind)
	{
	  return working_directory;
	});
	__gml_vm_greenvar("event_data", function (_set, _v, _ind)
	{
	  return event_data;
	});
	__gml_vm_greenvar("keyboard_key", function (_set, _v, _ind)
	{
	  if (_set) keyboard_key = _v;
	  return keyboard_key;
	});
	__gml_vm_greenvar("keyboard_lastchar", function (_set, _v, _ind)
	{
	  if (_set) keyboard_lastchar = _v;
	  return keyboard_lastchar;
	});
	__gml_vm_greenvar("keyboard_lastkey", function (_set, _v, _ind)
	{
	  if (_set) keyboard_lastkey = _v;
	  return keyboard_lastkey;
	});
	__gml_vm_greenvar("keyboard_string", function (_set, _v, _ind)
	{
	  if (_set) keyboard_string = _v;
	  return keyboard_string;
	});
	__gml_vm_greenvar("mouse_button", function (_set, _v, _ind)
	{
	  if (_set) mouse_button = _v;
	  return mouse_button;
	});
	__gml_vm_greenvar("mouse_lastbutton", function (_set, _v, _ind)
	{
	  if (_set) mouse_lastbutton = _v;
	  return mouse_lastbutton;
	});
	__gml_vm_greenvar("mouse_x", function (_set, _v, _ind)
	{
	  return mouse_x;
	});
	__gml_vm_greenvar("mouse_y", function (_set, _v, _ind)
	{
	  return mouse_y;
	});
	__gml_vm_greenvar("cursor_sprite", function (_set, _v, _ind)
	{
	  if (_set) cursor_sprite = _v;
	  return cursor_sprite;
	});
	__gml_vm_greenvar("game_display_name", function (_set, _v, _ind)
	{
	  return game_display_name;
	});
	__gml_vm_greenvar("game_id", function (_set, _v, _ind)
	{
	  return game_id;
	});
	__gml_vm_greenvar("game_project_name", function (_set, _v, _ind)
	{
	  return game_project_name;
	});
	__gml_vm_greenvar("game_save_id", function (_set, _v, _ind)
	{
	  return game_save_id;
	});
	__gml_vm_greenvar("current_day", function (_set, _v, _ind)
	{
	  return current_day;
	});
	__gml_vm_greenvar("current_hour", function (_set, _v, _ind)
	{
	  return current_hour;
	});
	__gml_vm_greenvar("current_minute", function (_set, _v, _ind)
	{
	  return current_minute;
	});
	__gml_vm_greenvar("current_month", function (_set, _v, _ind)
	{
	  return current_month;
	});
	__gml_vm_greenvar("current_second", function (_set, _v, _ind)
	{
	  return current_second;
	});
	__gml_vm_greenvar("current_time", function (_set, _v, _ind)
	{
	  return current_time;
	});
	__gml_vm_greenvar("current_weekday", function (_set, _v, _ind)
	{
	  return current_weekday;
	});
	__gml_vm_greenvar("current_year", function (_set, _v, _ind)
	{
	  return current_year;
	});
	__gml_vm_greenvar("delta_time", function (_set, _v, _ind)
	{
	  return delta_time;
	});
	__gml_vm_greenvar("os_browser", function (_set, _v, _ind)
	{
	  return os_browser;
	});
	__gml_vm_greenvar("os_device", function (_set, _v, _ind)
	{
	  return os_device;
	});
	__gml_vm_greenvar("os_type", function (_set, _v, _ind)
	{
	  return os_type;
	});
	__gml_vm_greenvar("os_version", function (_set, _v, _ind)
	{
	  return os_version;
	});
	__gml_vm_greenvar("phy_active", function (_set, _v, _ind)
	{
	  if (_set) phy_active = _v;
	  return phy_active;
	});
	__gml_vm_greenvar("phy_angular_damping", function (_set, _v, _ind)
	{
	  if (_set) phy_angular_damping = _v;
	  return phy_angular_damping;
	});
	__gml_vm_greenvar("phy_angular_velocity", function (_set, _v, _ind)
	{
	  if (_set) phy_angular_velocity = _v;
	  return phy_angular_velocity;
	});
	__gml_vm_greenvar("phy_bullet", function (_set, _v, _ind)
	{
	  if (_set) phy_bullet = _v;
	  return phy_bullet;
	});
	__gml_vm_greenvar("phy_collision_points", function (_set, _v, _ind)
	{
	  return phy_collision_points;
	});
	__gml_vm_greenvar("phy_collision_x", function (_set, _v, _ind)
	{
	  return phy_collision_x[_ind];
	}, true);
	__gml_vm_greenvar("phy_collision_y", function (_set, _v, _ind)
	{
	  return phy_collision_y[_ind];
	}, true);
	__gml_vm_greenvar("phy_col_normal_x", function (_set, _v, _ind)
	{
	  return phy_col_normal_x;
	});
	__gml_vm_greenvar("phy_col_normal_y", function (_set, _v, _ind)
	{
	  return phy_col_normal_y;
	});
	__gml_vm_greenvar("phy_com_x", function (_set, _v, _ind)
	{
	  return phy_com_x;
	});
	__gml_vm_greenvar("phy_com_y", function (_set, _v, _ind)
	{
	  return phy_com_y;
	});
	__gml_vm_greenvar("phy_dynamic", function (_set, _v, _ind)
	{
	  return phy_dynamic;
	});
	__gml_vm_greenvar("phy_fixed_rotation", function (_set, _v, _ind)
	{
	  if (_set) phy_fixed_rotation = _v;
	  return phy_fixed_rotation;
	});
	__gml_vm_greenvar("phy_inertia", function (_set, _v, _ind)
	{
	  return phy_inertia;
	});
	__gml_vm_greenvar("phy_kinematic", function (_set, _v, _ind)
	{
	  return phy_kinematic;
	});
	__gml_vm_greenvar("phy_linear_damping", function (_set, _v, _ind)
	{
	  if (_set) phy_linear_damping = _v;
	  return phy_linear_damping;
	});
	__gml_vm_greenvar("phy_linear_velocity_x", function (_set, _v, _ind)
	{
	  if (_set) phy_linear_velocity_x = _v;
	  return phy_linear_velocity_x;
	});
	__gml_vm_greenvar("phy_linear_velocity_y", function (_set, _v, _ind)
	{
	  if (_set) phy_linear_velocity_y = _v;
	  return phy_linear_velocity_y;
	});
	__gml_vm_greenvar("phy_mass", function (_set, _v, _ind)
	{
	  return phy_mass;
	});
	__gml_vm_greenvar("phy_position_x", function (_set, _v, _ind)
	{
	  if (_set) phy_position_x = _v;
	  return phy_position_x;
	});
	__gml_vm_greenvar("phy_position_xprevious", function (_set, _v, _ind)
	{
	  return phy_position_xprevious;
	});
	__gml_vm_greenvar("phy_position_y", function (_set, _v, _ind)
	{
	  if (_set) phy_position_y = _v;
	  return phy_position_y;
	});
	__gml_vm_greenvar("phy_position_yprevious", function (_set, _v, _ind)
	{
	  return phy_position_yprevious;
	});
	__gml_vm_greenvar("phy_rotation", function (_set, _v, _ind)
	{
	  if (_set) phy_rotation = _v;
	  return phy_rotation;
	});
	__gml_vm_greenvar("phy_sleeping", function (_set, _v, _ind)
	{
	  return phy_sleeping;
	});
	__gml_vm_greenvar("phy_speed", function (_set, _v, _ind)
	{
	  return phy_speed;
	});
	__gml_vm_greenvar("phy_speed_x", function (_set, _v, _ind)
	{
	  if (_set) phy_speed_x = _v;
	  return phy_speed_x;
	});
	__gml_vm_greenvar("phy_speed_y", function (_set, _v, _ind)
	{
	  if (_set) phy_speed_y = _v;
	  return phy_speed_y;
	});
	__gml_vm_greenvar("browser_height", function (_set, _v, _ind)
	{
	  return browser_height;
	});
	__gml_vm_greenvar("browser_width", function (_set, _v, _ind)
	{
	  return browser_width;
	});
	__gml_vm_greenvar("webgl_enabled", function (_set, _v, _ind)
	{
	  return webgl_enabled;
	});
	/*__gml_vm_greenvar("argument_relative", function (_set, _v, _ind)
	{
	  return argument_relative;
	});*/
	__gml_vm_greenvar("in_collision_tree", function (_set, _v, _ind)
	{
	  return in_collision_tree;
	});
	__gml_vm_greenvar("room_speed", function (_set, _v, _ind)
	{
	  if (_set) room_speed = _v;
	  return room_speed;
	});
	/*__gml_vm_greenvar("room_caption", function (_set, _v, _ind)
	{
	  if (_set) room_caption = _v;
	  return room_caption;
	});*/
	__gml_vm_greenvar("score", function (_set, _v, _ind)
	{
	  if (_set) score = _v;
	  return score;
	});
	__gml_vm_greenvar("lives", function (_set, _v, _ind)
	{
	  if (_set) lives = _v;
	  return lives;
	});
	__gml_vm_greenvar("health", function (_set, _v, _ind)
	{
	  if (_set) health = _v;
	  return health;
	});
	/*__gml_vm_greenvar("show_score", function (_set, _v, _ind)
	{
	  if (_set) show_score = _v;
	  return show_score;
	});
	__gml_vm_greenvar("show_lives", function (_set, _v, _ind)
	{
	  if (_set) show_lives = _v;
	  return show_lives;
	});
	__gml_vm_greenvar("show_health", function (_set, _v, _ind)
	{
	  if (_set) show_health = _v;
	  return show_health;
	});
	__gml_vm_greenvar("caption_score", function (_set, _v, _ind)
	{
	  if (_set) caption_score = _v;
	  return caption_score;
	});
	__gml_vm_greenvar("caption_lives", function (_set, _v, _ind)
	{
	  if (_set) caption_lives = _v;
	  return caption_lives;
	});
	__gml_vm_greenvar("caption_health", function (_set, _v, _ind)
	{
	  if (_set) caption_health = _v;
	  return caption_health;
	});*/
	__gml_vm_greenvar("event_action", function (_set, _v, _ind)
	{
	  return event_action;
	});
	/*__gml_vm_greenvar("gamemaker_pro", function (_set, _v, _ind)
	{
	  return gamemaker_pro;
	});
	__gml_vm_greenvar("gamemaker_registered", function (_set, _v, _ind)
	{
	  return gamemaker_registered;
	});
	__gml_vm_greenvar("error_occurred", function (_set, _v, _ind)
	{
	  if (_set) error_occurred = _v;
	  return error_occurred;
	});
	__gml_vm_greenvar("error_last", function (_set, _v, _ind)
	{
	  if (_set) error_last = _v;
	  return error_last;
	});*/
	__gml_vm_greenvar("background_colour", function (_set, _v, _ind)
	{
	  if (_set) background_colour = _v;
	  return background_colour;
	});
	__gml_vm_greenvar("background_showcolour", function (_set, _v, _ind)
	{
	  if (_set) background_showcolour = _v;
	  return background_showcolour;
	});
	__gml_vm_greenvar("background_color", function (_set, _v, _ind)
	{
	  if (_set) background_color = _v;
	  return background_color;
	});
	__gml_vm_greenvar("background_showcolor", function (_set, _v, _ind)
	{
	  if (_set) background_showcolor = _v;
	  return background_showcolor;
	});
	__gml_vm_greenvar("display_aa", function (_set, _v, _ind)
	{
	  return display_aa;
	});
	__gml_vm_greenvar("async_load", function (_set, _v, _ind)
	{
	  return async_load;
	});
	__gml_vm_greenvar("iap_data", function (_set, _v, _ind)
	{
	  return iap_data;
	});
	__gml_vm_greenvar("rollback_current_frame", function (_set, _v, _ind)
	{
	  return rollback_current_frame;
	});
	__gml_vm_greenvar("rollback_confirmed_frame", function (_set, _v, _ind)
	{
	  return rollback_confirmed_frame;
	});
	__gml_vm_greenvar("rollback_event_id", function (_set, _v, _ind)
	{
	  return rollback_event_id;
	});
	__gml_vm_greenvar("rollback_event_param", function (_set, _v, _ind)
	{
	  return rollback_event_param;
	});
	__gml_vm_greenvar("rollback_game_running", function (_set, _v, _ind)
	{
	  return rollback_game_running;
	});
	__gml_vm_greenvar("rollback_api_server", function (_set, _v, _ind)
	{
	  return rollback_api_server;
	});
	__gml_vm_greenvar("player_id", function (_set, _v, _ind)
	{
	  return player_id;
	});
	__gml_vm_greenvar("player_local", function (_set, _v, _ind)
	{
	  return player_local;
	});
	__gml_vm_greenvar("player_avatar_url", function (_set, _v, _ind)
	{
	  return player_avatar_url;
	});
	__gml_vm_greenvar("player_avatar_sprite", function (_set, _v, _ind)
	{
	  return player_avatar_sprite;
	});
	__gml_vm_greenvar("player_type", function (_set, _v, _ind)
	{
	  return player_type;
	});
	__gml_vm_greenvar("player_user_id", function (_set, _v, _ind)
	{
	  return player_user_id;
	});
	__gml_vm_greenvar("wallpaper_config", function (_set, _v, _ind)
	{
	  return wallpaper_config;
	});
}
#endregion

#region constants
// If you get an error about something not being found here, that means this constant isn't supported on your GameMaker version
// Just comment it out or replace the value with "undefined"
function __gml_init_constants()
{
	__gml.vm_constants = {
	    "sprite_add_ext_error_unknown": sprite_add_ext_error_unknown,
	    "sprite_add_ext_error_cancelled": sprite_add_ext_error_cancelled,
	    "sprite_add_ext_error_spritenotfound": sprite_add_ext_error_spritenotfound,
	    "sprite_add_ext_error_loadfailed": sprite_add_ext_error_loadfailed,
	    "sprite_add_ext_error_decompressfailed": sprite_add_ext_error_decompressfailed,
	    "sprite_add_ext_error_setupfailed": sprite_add_ext_error_setupfailed,
	    "video_format_rgba": video_format_rgba,
	    "video_format_yuv": video_format_yuv,
	    "video_status_closed": video_status_closed,
	    "video_status_preparing": video_status_preparing,
	    "video_status_playing": video_status_playing,
	    "video_status_paused": video_status_paused,
	    "ps5_share_feature_video_recording": ps5_share_feature_video_recording,
	    "ps5_share_feature_screenshot": ps5_share_feature_screenshot,
	    "ps5_share_feature_broadcast": ps5_share_feature_broadcast,
	    "ps5_share_feature_remote_play": ps5_share_feature_remote_play,
	    "ps5_share_feature_shareplay": ps5_share_feature_shareplay,
	    "ps5_share_feature_screenshare": ps5_share_feature_screenshare,
	    "ps5_share_feature_all": ps5_share_feature_all,
	    "ps5_gamepad_vibration_mode_advanced": ps5_gamepad_vibration_mode_advanced,
	    "ps5_gamepad_vibration_mode_compatible": ps5_gamepad_vibration_mode_compatible,
	    "ps5_gamepad_trigger_effect_state_off": ps5_gamepad_trigger_effect_state_off,
	    "ps5_gamepad_trigger_effect_state_feedback_standby": ps5_gamepad_trigger_effect_state_feedback_standby,
	    "ps5_gamepad_trigger_effect_state_feedback_active": ps5_gamepad_trigger_effect_state_feedback_active,
	    "ps5_gamepad_trigger_effect_state_weapon_standby": ps5_gamepad_trigger_effect_state_weapon_standby,
	    "ps5_gamepad_trigger_effect_state_weapon_pulling": ps5_gamepad_trigger_effect_state_weapon_pulling,
	    "ps5_gamepad_trigger_effect_state_weapon_fired": ps5_gamepad_trigger_effect_state_weapon_fired,
	    "ps5_gamepad_trigger_effect_state_vibration_standby": ps5_gamepad_trigger_effect_state_vibration_standby,
	    "ps5_gamepad_trigger_effect_state_vibration_active": ps5_gamepad_trigger_effect_state_vibration_active,
	    "ps5_gamepad_trigger_effect_state_intercepted": ps5_gamepad_trigger_effect_state_intercepted,
	    "ps5_fileerror_nospace": ps5_fileerror_nospace,
	    "psn_webapi_get": psn_webapi_get,
	    "psn_webapi_post": psn_webapi_post,
	    "psn_webapi_put": psn_webapi_put,
	    "psn_webapi_delete": psn_webapi_delete,
	    "xboxlive_achievement_filter_all_players": xboxlive_achievement_filter_all_players,
	    "xboxlive_achievement_filter_friends_only": xboxlive_achievement_filter_friends_only,
	    "xboxlive_achievement_filter_favorites_only": xboxlive_achievement_filter_favorites_only,
	    "xboxlive_achievement_filter_friends_alt": xboxlive_achievement_filter_friends_alt,
	    "xboxlive_achievement_filter_favorites_alt": xboxlive_achievement_filter_favorites_alt,
	    //"self": self,
	    //"other": other,
	    "all": all,
	    "noone": noone,
	    "true": true,
	    "false": false,
        "undefined": undefined,
        "NaN": NaN,
	    "pi": pi,
	    "infinity": infinity,
	    "pointer_null": pointer_null,
	    "pointer_invalid": pointer_invalid,
	    "pr_pointlist": pr_pointlist,
	    "pr_linelist": pr_linelist,
	    "pr_linestrip": pr_linestrip,
	    "pr_trianglelist": pr_trianglelist,
	    "pr_trianglestrip": pr_trianglestrip,
	    "pr_trianglefan": pr_trianglefan,
	    "c_aqua": c_aqua,
	    "c_black": c_black,
	    "c_blue": c_blue,
	    "c_dkgray": c_dkgray,
	    "c_dkgrey": c_dkgrey,
	    "c_fuchsia": c_fuchsia,
	    "c_gray": c_gray,
	    "c_grey": c_grey,
	    "c_green": c_green,
	    "c_lime": c_lime,
	    "c_ltgray": c_ltgray,
	    "c_ltgrey": c_ltgrey,
	    "c_maroon": c_maroon,
	    "c_navy": c_navy,
	    "c_olive": c_olive,
	    "c_purple": c_purple,
	    "c_red": c_red,
	    "c_silver": c_silver,
	    "c_teal": c_teal,
	    "c_white": c_white,
	    "c_yellow": c_yellow,
	    "c_orange": c_orange,
	    //"bm_complex": bm_complex,
	    "bm_normal": bm_normal,
	    "bm_add": bm_add,
	    "bm_max": bm_max,
	    "bm_subtract": bm_subtract,
	    "bm_min": bm_min,
	    "bm_reverse_subtract": bm_reverse_subtract,
	    "bm_zero": bm_zero,
	    "bm_one": bm_one,
	    "bm_src_color": bm_src_color,
	    "bm_inv_src_color": bm_inv_src_color,
	    "bm_src_colour": bm_src_colour,
	    "bm_inv_src_colour": bm_inv_src_colour,
	    "bm_src_alpha": bm_src_alpha,
	    "bm_inv_src_alpha": bm_inv_src_alpha,
	    "bm_dest_alpha": bm_dest_alpha,
	    "bm_inv_dest_alpha": bm_inv_dest_alpha,
	    "bm_dest_color": bm_dest_color,
	    "bm_inv_dest_color": bm_inv_dest_color,
	    "bm_dest_colour": bm_dest_colour,
	    "bm_inv_dest_colour": bm_inv_dest_colour,
	    "bm_src_alpha_sat": bm_src_alpha_sat,
	    "bm_eq_add": bm_eq_add,
	    "bm_eq_max": bm_eq_max,
	    "bm_eq_subtract": bm_eq_subtract,
	    "bm_eq_min": bm_eq_min,
	    "bm_eq_reverse_subtract": bm_eq_reverse_subtract,
	    "tf_point": tf_point,
	    "tf_linear": tf_linear,
	    "tf_anisotropic": tf_anisotropic,
	    "mip_off": mip_off,
	    "mip_on": mip_on,
	    "mip_markedonly": mip_markedonly,
	    "audio_falloff_none": audio_falloff_none,
	    "audio_falloff_inverse_distance": audio_falloff_inverse_distance,
	    "audio_falloff_inverse_distance_clamped": audio_falloff_inverse_distance_clamped,
	    "audio_falloff_inverse_distance_scaled": audio_falloff_inverse_distance_scaled,
	    "audio_falloff_linear_distance": audio_falloff_linear_distance,
	    "audio_falloff_linear_distance_clamped": audio_falloff_linear_distance_clamped,
	    "audio_falloff_exponent_distance": audio_falloff_exponent_distance,
	    "audio_falloff_exponent_distance_clamped": audio_falloff_exponent_distance_clamped,
	    "audio_falloff_exponent_distance_scaled": audio_falloff_exponent_distance_scaled,
	    "audio_old_system": audio_old_system,
	    "audio_new_system": audio_new_system,
	    "audio_mono": audio_mono,
	    "audio_stereo": audio_stereo,
	    "audio_3d": audio_3d,
	    "fa_left": fa_left,
	    "fa_center": fa_center,
	    "fa_right": fa_right,
	    "fa_top": fa_top,
	    "fa_middle": fa_middle,
	    "fa_bottom": fa_bottom,
	    "mb_any": mb_any,
	    "mb_none": mb_none,
	    "mb_left": mb_left,
	    "mb_right": mb_right,
	    "mb_middle": mb_middle,
	    "mb_side1": mb_side1,
	    "mb_side2": mb_side2,
	    "m_axisx": m_axisx,
	    "m_axisy": m_axisy,
	    "m_axisx_gui": m_axisx_gui,
	    "m_axisy_gui": m_axisy_gui,
	    "m_scroll_up": m_scroll_up,
	    "m_scroll_down": m_scroll_down,
	    "vk_nokey": vk_nokey,
	    "vk_anykey": vk_anykey,
	    "vk_enter": vk_enter,
	    "vk_return": vk_return,
	    "vk_shift": vk_shift,
	    "vk_control": vk_control,
	    "vk_alt": vk_alt,
	    "vk_escape": vk_escape,
	    "vk_space": vk_space,
	    "vk_backspace": vk_backspace,
	    "vk_tab": vk_tab,
	    "vk_pause": vk_pause,
	    "vk_printscreen": vk_printscreen,
	    "vk_left": vk_left,
	    "vk_right": vk_right,
	    "vk_up": vk_up,
	    "vk_down": vk_down,
	    "vk_home": vk_home,
	    "vk_end": vk_end,
	    "vk_delete": vk_delete,
	    "vk_insert": vk_insert,
	    "vk_pageup": vk_pageup,
	    "vk_pagedown": vk_pagedown,
	    "vk_f1": vk_f1,
	    "vk_f2": vk_f2,
	    "vk_f3": vk_f3,
	    "vk_f4": vk_f4,
	    "vk_f5": vk_f5,
	    "vk_f6": vk_f6,
	    "vk_f7": vk_f7,
	    "vk_f8": vk_f8,
	    "vk_f9": vk_f9,
	    "vk_f10": vk_f10,
	    "vk_f11": vk_f11,
	    "vk_f12": vk_f12,
	    "vk_numpad0": vk_numpad0,
	    "vk_numpad1": vk_numpad1,
	    "vk_numpad2": vk_numpad2,
	    "vk_numpad3": vk_numpad3,
	    "vk_numpad4": vk_numpad4,
	    "vk_numpad5": vk_numpad5,
	    "vk_numpad6": vk_numpad6,
	    "vk_numpad7": vk_numpad7,
	    "vk_numpad8": vk_numpad8,
	    "vk_numpad9": vk_numpad9,
	    "vk_divide": vk_divide,
	    "vk_multiply": vk_multiply,
	    "vk_subtract": vk_subtract,
	    "vk_add": vk_add,
	    "vk_decimal": vk_decimal,
	    "vk_lshift": vk_lshift,
	    "vk_lcontrol": vk_lcontrol,
	    "vk_lalt": vk_lalt,
	    "vk_rshift": vk_rshift,
	    "vk_rcontrol": vk_rcontrol,
	    "vk_ralt": vk_ralt,
	    "gp_face1": gp_face1,
	    "gp_face2": gp_face2,
	    "gp_face3": gp_face3,
	    "gp_face4": gp_face4,
	    "gp_shoulderl": gp_shoulderl,
	    "gp_shoulderr": gp_shoulderr,
	    "gp_shoulderlb": gp_shoulderlb,
	    "gp_shoulderrb": gp_shoulderrb,
	    "gp_select": gp_select,
	    "gp_start": gp_start,
	    "gp_stickl": gp_stickl,
	    "gp_stickr": gp_stickr,
	    "gp_padu": gp_padu,
	    "gp_padd": gp_padd,
	    "gp_padl": gp_padl,
	    "gp_padr": gp_padr,
	    "gp_axislh": gp_axislh,
	    "gp_axislv": gp_axislv,
	    "gp_axisrh": gp_axisrh,
	    "gp_axisrv": gp_axisrv,
	    "gp_axis_acceleration_x": gp_axis_acceleration_x,
	    "gp_axis_acceleration_y": gp_axis_acceleration_y,
	    "gp_axis_acceleration_z": gp_axis_acceleration_z,
	    "gp_axis_angular_velocity_x": gp_axis_angular_velocity_x,
	    "gp_axis_angular_velocity_y": gp_axis_angular_velocity_y,
	    "gp_axis_angular_velocity_z": gp_axis_angular_velocity_z,
	    "gp_axis_orientation_x": gp_axis_orientation_x,
	    "gp_axis_orientation_y": gp_axis_orientation_y,
	    "gp_axis_orientation_z": gp_axis_orientation_z,
	    "gp_axis_orientation_w": gp_axis_orientation_w,
	    "gp_home": gp_home,
	    "gp_extra1": gp_extra1,
	    "gp_extra2": gp_extra2,
	    "gp_extra3": gp_extra3,
	    "gp_extra4": gp_extra4,
	    "gp_paddler": gp_paddler,
	    "gp_paddlel": gp_paddlel,
	    "gp_paddlerb": gp_paddlerb,
	    "gp_paddlelb": gp_paddlelb,
	    "gp_touchpadbutton": gp_touchpadbutton,
	    "gp_extra5": gp_extra5,
	    "gp_extra6": gp_extra6,
	    "time_source_global": time_source_global,
	    "time_source_game": time_source_game,
	    "time_source_units_seconds": time_source_units_seconds,
	    "time_source_units_frames": time_source_units_frames,
	    "time_source_expire_nearest": time_source_expire_nearest,
	    "time_source_expire_after": time_source_expire_after,
	    "time_source_state_initial": time_source_state_initial,
	    "time_source_state_active": time_source_state_active,
	    "time_source_state_paused": time_source_state_paused,
	    "time_source_state_stopped": time_source_state_stopped,
	    "debug_input_filter_mouse": debug_input_filter_mouse,
	    "debug_input_filter_touch": debug_input_filter_touch,
	    "debug_input_filter_keyboard": debug_input_filter_keyboard,
	    "ev_create": ev_create,
	    "ev_destroy": ev_destroy,
	    "ev_step": ev_step,
	    "ev_alarm": ev_alarm,
	    "ev_keyboard": ev_keyboard,
	    "ev_mouse": ev_mouse,
	    "ev_collision": ev_collision,
	    "ev_other": ev_other,
	    "ev_draw": ev_draw,
	    "ev_keypress": ev_keypress,
	    "ev_keyrelease": ev_keyrelease,
	    "ev_trigger": ev_trigger,
	    "ev_cleanup": ev_cleanup,
	    "ev_gesture": ev_gesture,
	    //"ev_pre_create": ev_pre_create,
	    "ev_left_button": ev_left_button,
	    "ev_right_button": ev_right_button,
	    "ev_middle_button": ev_middle_button,
	    "ev_no_button": ev_no_button,
	    "ev_left_press": ev_left_press,
	    "ev_right_press": ev_right_press,
	    "ev_middle_press": ev_middle_press,
	    "ev_left_release": ev_left_release,
	    "ev_right_release": ev_right_release,
	    "ev_middle_release": ev_middle_release,
	    "ev_mouse_enter": ev_mouse_enter,
	    "ev_mouse_leave": ev_mouse_leave,
	    //"ev_global_press": ev_global_press,
	    //"ev_global_release": ev_global_release,
	    "ev_joystick1_left": ev_joystick1_left,
	    "ev_joystick1_right": ev_joystick1_right,
	    "ev_joystick1_up": ev_joystick1_up,
	    "ev_joystick1_down": ev_joystick1_down,
	    "ev_joystick1_button1": ev_joystick1_button1,
	    "ev_joystick1_button2": ev_joystick1_button2,
	    "ev_joystick1_button3": ev_joystick1_button3,
	    "ev_joystick1_button4": ev_joystick1_button4,
	    "ev_joystick1_button5": ev_joystick1_button5,
	    "ev_joystick1_button6": ev_joystick1_button6,
	    "ev_joystick1_button7": ev_joystick1_button7,
	    "ev_joystick1_button8": ev_joystick1_button8,
	    "ev_joystick2_left": ev_joystick2_left,
	    "ev_joystick2_right": ev_joystick2_right,
	    "ev_joystick2_up": ev_joystick2_up,
	    "ev_joystick2_down": ev_joystick2_down,
	    "ev_joystick2_button1": ev_joystick2_button1,
	    "ev_joystick2_button2": ev_joystick2_button2,
	    "ev_joystick2_button3": ev_joystick2_button3,
	    "ev_joystick2_button4": ev_joystick2_button4,
	    "ev_joystick2_button5": ev_joystick2_button5,
	    "ev_joystick2_button6": ev_joystick2_button6,
	    "ev_joystick2_button7": ev_joystick2_button7,
	    "ev_joystick2_button8": ev_joystick2_button8,
	    "ev_global_left_button": ev_global_left_button,
	    "ev_global_right_button": ev_global_right_button,
	    "ev_global_middle_button": ev_global_middle_button,
	    "ev_global_left_press": ev_global_left_press,
	    "ev_global_right_press": ev_global_right_press,
	    "ev_global_middle_press": ev_global_middle_press,
	    "ev_global_left_release": ev_global_left_release,
	    "ev_global_right_release": ev_global_right_release,
	    "ev_global_middle_release": ev_global_middle_release,
	    "ev_mouse_wheel_up": ev_mouse_wheel_up,
	    "ev_mouse_wheel_down": ev_mouse_wheel_down,
	    "ev_outside": ev_outside,
	    "ev_boundary": ev_boundary,
	    "ev_game_start": ev_game_start,
	    "ev_game_end": ev_game_end,
	    "ev_room_start": ev_room_start,
	    "ev_room_end": ev_room_end,
	    "ev_no_more_lives": ev_no_more_lives,
	    "ev_animation_end": ev_animation_end,
	    "ev_end_of_path": ev_end_of_path,
	    "ev_no_more_health": ev_no_more_health,
	    "ev_user0": ev_user0,
	    "ev_user1": ev_user1,
	    "ev_user2": ev_user2,
	    "ev_user3": ev_user3,
	    "ev_user4": ev_user4,
	    "ev_user5": ev_user5,
	    "ev_user6": ev_user6,
	    "ev_user7": ev_user7,
	    "ev_user8": ev_user8,
	    "ev_user9": ev_user9,
	    "ev_user10": ev_user10,
	    "ev_user11": ev_user11,
	    "ev_user12": ev_user12,
	    "ev_user13": ev_user13,
	    "ev_user14": ev_user14,
	    "ev_user15": ev_user15,
	    //"ev_close_button": ev_close_button,
	    "ev_outside_view0": ev_outside_view0,
	    "ev_outside_view1": ev_outside_view1,
	    "ev_outside_view2": ev_outside_view2,
	    "ev_outside_view3": ev_outside_view3,
	    "ev_outside_view4": ev_outside_view4,
	    "ev_outside_view5": ev_outside_view5,
	    "ev_outside_view6": ev_outside_view6,
	    "ev_outside_view7": ev_outside_view7,
	    "ev_boundary_view0": ev_boundary_view0,
	    "ev_boundary_view1": ev_boundary_view1,
	    "ev_boundary_view2": ev_boundary_view2,
	    "ev_boundary_view3": ev_boundary_view3,
	    "ev_boundary_view4": ev_boundary_view4,
	    "ev_boundary_view5": ev_boundary_view5,
	    "ev_boundary_view6": ev_boundary_view6,
	    "ev_boundary_view7": ev_boundary_view7,
	    "ev_animation_update": ev_animation_update,
	    "ev_animation_event": ev_animation_event,
	    "ev_web_image_load": ev_web_image_load,
	    "ev_web_sound_load": ev_web_sound_load,
	    "ev_web_async": ev_web_async,
	    "ev_dialog_async": ev_dialog_async,
	    "ev_web_iap": ev_web_iap,
	    "ev_web_cloud": ev_web_cloud,
	    "ev_web_networking": ev_web_networking,
	    "ev_web_steam": ev_web_steam,
	    "ev_social": ev_social,
	    "ev_push_notification": ev_push_notification,
	    "ev_audio_recording": ev_audio_recording,
	    "ev_audio_playback": ev_audio_playback,
	    "ev_system_event": ev_system_event,
	    "ev_broadcast_message": ev_broadcast_message,
	    "ev_audio_playback_ended": ev_audio_playback_ended,
	    "ev_async_web_image_load": ev_async_web_image_load,
	    "ev_async_web": ev_async_web,
	    "ev_async_dialog": ev_async_dialog,
	    "ev_async_web_iap": ev_async_web_iap,
	    "ev_async_web_cloud": ev_async_web_cloud,
	    "ev_async_web_networking": ev_async_web_networking,
	    "ev_async_web_steam": ev_async_web_steam,
	    "ev_async_social": ev_async_social,
	    "ev_async_push_notification": ev_async_push_notification,
	    "ev_async_save_load": ev_async_save_load,
	    "ev_async_audio_recording": ev_async_audio_recording,
	    "ev_async_audio_playback": ev_async_audio_playback,
	    "ev_async_system_event": ev_async_system_event,
	    "ev_async_audio_playback_ended": ev_async_audio_playback_ended,
	    "ev_step_normal": ev_step_normal,
	    "ev_step_begin": ev_step_begin,
	    "ev_step_end": ev_step_end,
	    "ev_gui": ev_gui,
	    "ev_draw_begin": ev_draw_begin,
	    "ev_draw_end": ev_draw_end,
	    "ev_gui_begin": ev_gui_begin,
	    "ev_gui_end": ev_gui_end,
	    "ev_draw_pre": ev_draw_pre,
	    "ev_draw_post": ev_draw_post,
	    "ev_draw_normal": ev_draw_normal,
	    "ev_gesture_tap": ev_gesture_tap,
	    "ev_gesture_double_tap": ev_gesture_double_tap,
	    "ev_gesture_drag_start": ev_gesture_drag_start,
	    "ev_gesture_dragging": ev_gesture_dragging,
	    "ev_gesture_drag_end": ev_gesture_drag_end,
	    "ev_gesture_flick": ev_gesture_flick,
	    "ev_gesture_pinch_start": ev_gesture_pinch_start,
	    "ev_gesture_pinch_in": ev_gesture_pinch_in,
	    "ev_gesture_pinch_out": ev_gesture_pinch_out,
	    "ev_gesture_pinch_end": ev_gesture_pinch_end,
	    "ev_gesture_rotate_start": ev_gesture_rotate_start,
	    "ev_gesture_rotating": ev_gesture_rotating,
	    "ev_gesture_rotate_end": ev_gesture_rotate_end,
	    "ev_global_gesture_tap": ev_global_gesture_tap,
	    "ev_global_gesture_double_tap": ev_global_gesture_double_tap,
	    "ev_global_gesture_drag_start": ev_global_gesture_drag_start,
	    "ev_global_gesture_dragging": ev_global_gesture_dragging,
	    "ev_global_gesture_drag_end": ev_global_gesture_drag_end,
	    "ev_global_gesture_flick": ev_global_gesture_flick,
	    "ev_global_gesture_pinch_start": ev_global_gesture_pinch_start,
	    "ev_global_gesture_pinch_in": ev_global_gesture_pinch_in,
	    "ev_global_gesture_pinch_out": ev_global_gesture_pinch_out,
	    "ev_global_gesture_pinch_end": ev_global_gesture_pinch_end,
	    "ev_global_gesture_rotate_start": ev_global_gesture_rotate_start,
	    "ev_global_gesture_rotating": ev_global_gesture_rotating,
	    "ev_global_gesture_rotate_end": ev_global_gesture_rotate_end,
	    "ty_real": ty_real,
	    "ty_string": ty_string,
	    "dll_cdecl": dll_cdecl,
	    "dll_stdcall": dll_stdcall,
	    "fa_none": fa_none,
	    "fa_readonly": fa_readonly,
	    "fa_hidden": fa_hidden,
	    "fa_sysfile": fa_sysfile,
	    "fa_volumeid": fa_volumeid,
	    "fa_directory": fa_directory,
	    "fa_archive": fa_archive,
	    "cr_default": cr_default,
	    "cr_none": cr_none,
	    "cr_arrow": cr_arrow,
	    "cr_cross": cr_cross,
	    "cr_beam": cr_beam,
	    "cr_size_nesw": cr_size_nesw,
	    "cr_size_ns": cr_size_ns,
	    "cr_size_nwse": cr_size_nwse,
	    "cr_size_we": cr_size_we,
	    "cr_uparrow": cr_uparrow,
	    "cr_hourglass": cr_hourglass,
	    "cr_drag": cr_drag,
	    "cr_appstart": cr_appstart,
	    "cr_handpoint": cr_handpoint,
	    "cr_size_all": cr_size_all,
	    "pt_shape_pixel": pt_shape_pixel,
	    "pt_shape_disk": pt_shape_disk,
	    "pt_shape_square": pt_shape_square,
	    "pt_shape_line": pt_shape_line,
	    "pt_shape_star": pt_shape_star,
	    "pt_shape_circle": pt_shape_circle,
	    "pt_shape_ring": pt_shape_ring,
	    "pt_shape_sphere": pt_shape_sphere,
	    "pt_shape_flare": pt_shape_flare,
	    "pt_shape_spark": pt_shape_spark,
	    "pt_shape_explosion": pt_shape_explosion,
	    "pt_shape_cloud": pt_shape_cloud,
	    "pt_shape_smoke": pt_shape_smoke,
	    "pt_shape_snow": pt_shape_snow,
	    "ps_distr_linear": ps_distr_linear,
	    "ps_distr_gaussian": ps_distr_gaussian,
	    "ps_distr_invgaussian": ps_distr_invgaussian,
	    "ps_shape_rectangle": ps_shape_rectangle,
	    "ps_shape_ellipse": ps_shape_ellipse,
	    "ps_shape_diamond": ps_shape_diamond,
	    "ps_shape_line": ps_shape_line,
	    /*"ps_force_constant": ps_force_constant,
	    "ps_force_linear": ps_force_linear,
	    "ps_force_quadratic": ps_force_quadratic,
	    "ps_deflect_vertical": ps_deflect_vertical,
	    "ps_deflect_horizontal": ps_deflect_horizontal,
	    "ps_change_all": ps_change_all,
	    "ps_change_shape": ps_change_shape,
	    "ps_change_motion": ps_change_motion,*/
	    "ps_mode_stream": ps_mode_stream,
	    "ps_mode_burst": ps_mode_burst,
	    "ef_explosion": ef_explosion,
	    "ef_ring": ef_ring,
	    "ef_ellipse": ef_ellipse,
	    "ef_firework": ef_firework,
	    "ef_smoke": ef_smoke,
	    "ef_smokeup": ef_smokeup,
	    "ef_star": ef_star,
	    "ef_spark": ef_spark,
	    "ef_flare": ef_flare,
	    "ef_cloud": ef_cloud,
	    "ef_rain": ef_rain,
	    "ef_snow": ef_snow,
	    "display_landscape": display_landscape,
	    "display_portrait": display_portrait,
	    "display_landscape_flipped": display_landscape_flipped,
	    "display_portrait_flipped": display_portrait_flipped,
	    "os_unknown": os_unknown,
	    "os_win32": os_win32,
	    "os_windows": os_windows,
	    "os_macosx": os_macosx,
	    //"os_psp": os_psp,
	    "os_ios": os_ios,
	    "os_android": os_android,
	    //"os_symbian": os_symbian,
	    "os_linux": os_linux,
	    "os_winphone": os_winphone,
	    //"os_tizen": os_tizen,
	    "os_win8native": os_win8native,
	    //"os_wiiu": os_wiiu,
	    //"os_3ds": os_3ds,
	    "os_psvita": os_psvita,
	    //"os_bb10": os_bb10,
	    "os_ps4": os_ps4,
	    "os_xboxone": os_xboxone,
	    "os_ps3": os_ps3,
	    //"os_xbox360": os_xbox360,
	    "os_uwp": os_uwp,
	    "os_tvos": os_tvos,
	    "os_switch": os_switch,
	    "os_ps5": os_ps5,
	    "os_xboxseriesxs": os_xboxseriesxs,
	    "os_gdk": os_gdk,
	    "os_operagx": os_operagx,
	    "os_gxgames": os_gxgames,
	    /*"os_llvm_win32": os_llvm_win32,
	    "os_llvm_macosx": os_llvm_macosx,
	    "os_llvm_psp": os_llvm_psp,
	    "os_llvm_ios": os_llvm_ios,
	    "os_llvm_android": os_llvm_android,
	    "os_llvm_symbian": os_llvm_symbian,
	    "os_llvm_linux": os_llvm_linux,
	    "os_llvm_winphone": os_llvm_winphone,*/
	    "browser_not_a_browser": browser_not_a_browser,
	    "browser_unknown": browser_unknown,
	    "browser_ie": browser_ie,
	    "browser_firefox": browser_firefox,
	    "browser_chrome": browser_chrome,
	    "browser_safari": browser_safari,
	    "browser_safari_mobile": browser_safari_mobile,
	    "browser_opera": browser_opera,
	    //"browser_android_default": browser_android_default,
	    "browser_windows_store": browser_windows_store,
	    "browser_tizen": browser_tizen,
	    "browser_ie_mobile": browser_ie_mobile,
	    "browser_edge": browser_edge,
	    "asset_unknown": asset_unknown,
	    "asset_object": asset_object,
	    "asset_sprite": asset_sprite,
	    "asset_sound": asset_sound,
	    "asset_room": asset_room,
	    "asset_tiles": asset_tiles,
	    "asset_path": asset_path,
	    "asset_script": asset_script,
	    "asset_font": asset_font,
	    "asset_timeline": asset_timeline,
	    "asset_shader": asset_shader,
	    "asset_sequence": asset_sequence,
	    "asset_animationcurve": asset_animationcurve,
	    "asset_particlesystem": asset_particlesystem,
	    "layer_type_unknown": layer_type_unknown,
	    "layer_type_room": layer_type_room,
	    "layer_type_ui_viewports": layer_type_ui_viewports,
	    "layer_type_ui_display": layer_type_ui_display,
	    "device_ios_unknown": device_ios_unknown,
	    "device_ios_iphone": device_ios_iphone,
	    "device_ios_iphone_retina": device_ios_iphone_retina,
	    "device_ios_ipad": device_ios_ipad,
	    "device_ios_ipad_retina": device_ios_ipad_retina,
	    "device_ios_iphone5": device_ios_iphone5,
	    "device_ios_iphone6": device_ios_iphone6,
	    "device_ios_iphone6plus": device_ios_iphone6plus,
	    "device_ios_iphone6s": device_ios_iphone6s,
	    "device_ios_iphone6splus": device_ios_iphone6splus,
	    "device_emulator": device_emulator,
	    "device_tablet": device_tablet,
	    "of_challenge_win": of_challenge_win,
	    "of_challenge_lose": of_challenge_lose,
	    "of_challenge_tie": of_challenge_tie, // hi flingo
	    "leaderboard_type_number": leaderboard_type_number,
	    "leaderboard_type_time_mins_secs": leaderboard_type_time_mins_secs,
	    "phy_joint_anchor_1_x": phy_joint_anchor_1_x,
	    "phy_joint_anchor_1_y": phy_joint_anchor_1_y,
	    "phy_joint_anchor_2_x": phy_joint_anchor_2_x,
	    "phy_joint_anchor_2_y": phy_joint_anchor_2_y,
	    "phy_joint_reaction_force_x": phy_joint_reaction_force_x,
	    "phy_joint_reaction_force_y": phy_joint_reaction_force_y,
	    "phy_joint_reaction_torque": phy_joint_reaction_torque,
	    "phy_joint_motor_speed": phy_joint_motor_speed,
	    "phy_joint_angle": phy_joint_angle,
	    "phy_joint_motor_torque": phy_joint_motor_torque,
	    "phy_joint_max_motor_torque": phy_joint_max_motor_torque,
	    "phy_joint_translation": phy_joint_translation,
	    "phy_joint_speed": phy_joint_speed,
	    "phy_joint_motor_force": phy_joint_motor_force,
	    "phy_joint_max_motor_force": phy_joint_max_motor_force,
	    "phy_joint_length_1": phy_joint_length_1,
	    "phy_joint_length_2": phy_joint_length_2,
	    "phy_joint_damping_ratio": phy_joint_damping_ratio,
	    "phy_joint_frequency": phy_joint_frequency,
	    "phy_joint_lower_angle_limit": phy_joint_lower_angle_limit,
	    "phy_joint_upper_angle_limit": phy_joint_upper_angle_limit,
	    "phy_joint_angle_limits": phy_joint_angle_limits,
	    "phy_joint_max_length": phy_joint_max_length,
	    "phy_joint_max_torque": phy_joint_max_torque,
	    "phy_joint_max_force": phy_joint_max_force,
	    "phy_debug_render_shapes": phy_debug_render_shapes,
	    "phy_debug_render_joints": phy_debug_render_joints,
	    "phy_debug_render_coms": phy_debug_render_coms,
	    "phy_debug_render_aabb": phy_debug_render_aabb,
	    "phy_debug_render_obb": phy_debug_render_obb,
	    "phy_debug_render_core_shapes": phy_debug_render_core_shapes,
	    "phy_debug_render_collision_pairs": phy_debug_render_collision_pairs,
	    "phy_particle_flag_water": phy_particle_flag_water,
	    "phy_particle_flag_zombie": phy_particle_flag_zombie,
	    "phy_particle_flag_wall": phy_particle_flag_wall,
	    "phy_particle_flag_spring": phy_particle_flag_spring,
	    "phy_particle_flag_elastic": phy_particle_flag_elastic,
	    "phy_particle_flag_viscous": phy_particle_flag_viscous,
	    "phy_particle_flag_powder": phy_particle_flag_powder,
	    "phy_particle_flag_tensile": phy_particle_flag_tensile,
	    "phy_particle_flag_colourmixing": phy_particle_flag_colourmixing,
	    "phy_particle_flag_colormixing": phy_particle_flag_colormixing,
	    "phy_particle_group_flag_solid": phy_particle_group_flag_solid,
	    "phy_particle_group_flag_rigid": phy_particle_group_flag_rigid,
	    "phy_particle_data_flag_typeflags": phy_particle_data_flag_typeflags,
	    "phy_particle_data_flag_position": phy_particle_data_flag_position,
	    "phy_particle_data_flag_velocity": phy_particle_data_flag_velocity,
	    "phy_particle_data_flag_colour": phy_particle_data_flag_colour,
	    "phy_particle_data_flag_color": phy_particle_data_flag_color,
	    "phy_particle_data_flag_category": phy_particle_data_flag_category,
	    "achievement_our_info": achievement_our_info,
	    "achievement_friends_info": achievement_friends_info,
	    "achievement_leaderboard_info": achievement_leaderboard_info,
	    "achievement_achievement_info": achievement_achievement_info,
	    /*"achievement_filter_all_players": achievement_filter_all_players,
	    "achievement_filter_friends_only": achievement_filter_friends_only,
	    "achievement_filter_favorites_only": achievement_filter_favorites_only,
	    "achievement_filter_friends_alt": achievement_filter_friends_alt,
	    "achievement_filter_favorites_alt": achievement_filter_favorites_alt,
	    "achievement_type_achievement_challenge": achievement_type_achievement_challenge,
	    "achievement_type_score_challenge": achievement_type_score_challenge,*/
	    "achievement_pic_loaded": achievement_pic_loaded,
	    /*"achievement_challenge_completed": achievement_challenge_completed,
	    "achievement_challenge_completed_by_remote": achievement_challenge_completed_by_remote,
	    "achievement_challenge_received": achievement_challenge_received,
	    "achievement_challenge_list_received": achievement_challenge_list_received,
	    "achievement_challenge_launched": achievement_challenge_launched,
	    "achievement_player_info": achievement_player_info,
	    "achievement_purchase_info": achievement_purchase_info,
	    "achievement_msg_result": achievement_msg_result,
	    "achievement_stat_event": achievement_stat_event,*/
	    "achievement_show_ui": achievement_show_ui,
	    "achievement_show_profile": achievement_show_profile,
	    "achievement_show_leaderboard": achievement_show_leaderboard,
	    "achievement_show_achievement": achievement_show_achievement,
	    "achievement_show_bank": achievement_show_bank,
	    "achievement_show_friend_picker": achievement_show_friend_picker,
	    "achievement_show_purchase_prompt": achievement_show_purchase_prompt,
	    "buffer_fixed": buffer_fixed,
	    "buffer_grow": buffer_grow,
	    "buffer_wrap": buffer_wrap,
	    "buffer_fast": buffer_fast,
	    "buffer_vbuffer": buffer_vbuffer,
	    "buffer_u8": buffer_u8,
	    "buffer_s8": buffer_s8,
	    "buffer_u16": buffer_u16,
	    "buffer_s16": buffer_s16,
	    "buffer_u32": buffer_u32,
	    "buffer_s32": buffer_s32,
	    "buffer_f16": buffer_f16,
	    "buffer_f32": buffer_f32,
	    "buffer_f64": buffer_f64,
	    "buffer_bool": buffer_bool,
	    "buffer_string": buffer_string,
	    "buffer_u64": buffer_u64,
	    "buffer_text": buffer_text,
	    "buffer_seek_start": buffer_seek_start,
	    "buffer_seek_relative": buffer_seek_relative,
	    "buffer_seek_end": buffer_seek_end,
	    "buffer_error_general": buffer_error_general,
	    "buffer_error_out_of_space": buffer_error_out_of_space,
	    "buffer_error_invalid_type": buffer_error_invalid_type,
	    "network_socket_tcp": network_socket_tcp,
	    "network_socket_udp": network_socket_udp,
	    "network_socket_bluetooth": network_socket_bluetooth,
	    "network_socket_tcp_psn": network_socket_tcp_psn,
	    "network_socket_udp_psn": network_socket_udp_psn,
	    "network_socket_udp_switch": network_socket_udp_switch,
	    "network_socket_ws": network_socket_ws,
	    "network_socket_wss": network_socket_wss,
	    "network_type_connect": network_type_connect,
	    "network_type_disconnect": network_type_disconnect,
	    "network_type_data": network_type_data,
	    "network_type_non_blocking_connect": network_type_non_blocking_connect,
	    "network_type_up": network_type_up,
	    "network_type_up_failed": network_type_up_failed,
	    "network_type_down": network_type_down,
	    "network_config_connect_timeout": network_config_connect_timeout,
	    "network_config_use_non_blocking_socket": network_config_use_non_blocking_socket,
	    "network_config_enable_reliable_udp": network_config_enable_reliable_udp,
	    "network_config_disable_reliable_udp": network_config_disable_reliable_udp,
	    "network_config_avoid_time_wait": network_config_avoid_time_wait,
	    "network_config_websocket_protocol": network_config_websocket_protocol,
	    "network_config_enable_multicast": network_config_enable_multicast,
	    "network_config_disable_multicast": network_config_disable_multicast,
	    "network_connect_none": network_connect_none,
	    "network_connect_blocking": network_connect_blocking,
	    "network_connect_nonblocking": network_connect_nonblocking,
	    "network_connect_active": network_connect_active,
	    "network_connect_passive": network_connect_passive,
	    "network_send_binary": network_send_binary,
	    "network_send_text": network_send_text,
	    "vertex_usage_position": vertex_usage_position,
	    "vertex_usage_colour": vertex_usage_colour,
	    "vertex_usage_color": vertex_usage_color,
	    "vertex_usage_normal": vertex_usage_normal,
	    "vertex_usage_textcoord": vertex_usage_textcoord,
	    "vertex_usage_texcoord": vertex_usage_texcoord,
	    "vertex_usage_blendweight": vertex_usage_blendweight,
	    "vertex_usage_blendindices": vertex_usage_blendindices,
	    "vertex_usage_psize": vertex_usage_psize,
	    "vertex_usage_tangent": vertex_usage_tangent,
	    "vertex_usage_binormal": vertex_usage_binormal,
	    "vertex_usage_fog": vertex_usage_fog,
	    "vertex_usage_depth": vertex_usage_depth,
	    "vertex_usage_sample": vertex_usage_sample,
	    "vertex_type_float1": vertex_type_float1,
	    "vertex_type_float2": vertex_type_float2,
	    "vertex_type_float3": vertex_type_float3,
	    "vertex_type_float4": vertex_type_float4,
	    "vertex_type_colour": vertex_type_colour,
	    "vertex_type_color": vertex_type_color,
	    "vertex_type_ubyte4": vertex_type_ubyte4,
	    "ds_type_map": ds_type_map,
	    "ds_type_list": ds_type_list,
	    "ds_type_stack": ds_type_stack,
	    "ds_type_queue": ds_type_queue,
	    "ds_type_grid": ds_type_grid,
	    "ds_type_priority": ds_type_priority,
	    "iap_ev_storeload": iap_ev_storeload,
	    "iap_ev_product": iap_ev_product,
	    "iap_ev_purchase": iap_ev_purchase,
	    "iap_ev_consume": iap_ev_consume,
	    "iap_ev_restore": iap_ev_restore,
	    "iap_storeload_ok": iap_storeload_ok,
	    "iap_storeload_failed": iap_storeload_failed,
	    "iap_status_uninitialised": iap_status_uninitialised,
	    "iap_status_unavailable": iap_status_unavailable,
	    "iap_status_loading": iap_status_loading,
	    "iap_status_available": iap_status_available,
	    "iap_status_processing": iap_status_processing,
	    "iap_status_restoring": iap_status_restoring,
	    "iap_failed": iap_failed,
	    "iap_unavailable": iap_unavailable,
	    "iap_available": iap_available,
	    "iap_purchased": iap_purchased,
	    "iap_canceled": iap_canceled,
	    "iap_refunded": iap_refunded,
	    "matrix_view": matrix_view,
	    "matrix_projection": matrix_projection,
	    "matrix_world": matrix_world,
	    "timezone_local": timezone_local,
	    "timezone_utc": timezone_utc,
	    "gamespeed_fps": gamespeed_fps,
	    "gamespeed_microseconds": gamespeed_microseconds,
	    "spritespeed_framespersecond": spritespeed_framespersecond,
	    "spritespeed_framespergameframe": spritespeed_framespergameframe,
	    /*"xboxone_fileerror_noerror": xboxone_fileerror_noerror,
	    "xboxone_fileerror_outofmemory": xboxone_fileerror_outofmemory,
	    "xboxone_fileerror_usernotfound": xboxone_fileerror_usernotfound,
	    "xboxone_fileerror_unknownerror": xboxone_fileerror_unknownerror,
	    "xboxone_fileerror_cantopenfile": xboxone_fileerror_cantopenfile,
	    "xboxone_fileerror_blobnotfound": xboxone_fileerror_blobnotfound,
	    "xboxone_fileerror_containernotinsync": xboxone_fileerror_containernotinsync,
	    "xboxone_fileerror_containersyncfailed": xboxone_fileerror_containersyncfailed,
	    "xboxone_fileerror_invalidcontainername": xboxone_fileerror_invalidcontainername,
	    "xboxone_fileerror_noaccess": xboxone_fileerror_noaccess,
	    "xboxone_fileerror_noxboxliveinfo": xboxone_fileerror_noxboxliveinfo,
	    "xboxone_fileerror_outoflocalstorage": xboxone_fileerror_outoflocalstorage,
	    "xboxone_fileerror_providedbuffertoosmall": xboxone_fileerror_providedbuffertoosmall,
	    "xboxone_fileerror_quotaexceeded": xboxone_fileerror_quotaexceeded,
	    "xboxone_fileerror_updatetoobig": xboxone_fileerror_updatetoobig,
	    "xboxone_fileerror_usercanceled": xboxone_fileerror_usercanceled,
	    "xboxone_gamerpic_small": xboxone_gamerpic_small,
	    "xboxone_gamerpic_medium": xboxone_gamerpic_medium,
	    "xboxone_gamerpic_large": xboxone_gamerpic_large,
	    "xboxone_agegroup_unknown": xboxone_agegroup_unknown,
	    "xboxone_agegroup_child": xboxone_agegroup_child,
	    "xboxone_agegroup_teen": xboxone_agegroup_teen,
	    "xboxone_agegroup_adult": xboxone_agegroup_adult,
	    "xboxone_privilege_internet_browsing": xboxone_privilege_internet_browsing,
	    "xboxone_privilege_social_network_sharing": xboxone_privilege_social_network_sharing,
	    "xboxone_privilege_share_kinect_content": xboxone_privilege_share_kinect_content,
	    "xboxone_privilege_video_communications": xboxone_privilege_video_communications,
	    "xboxone_privilege_communications": xboxone_privilege_communications,
	    "xboxone_privilege_user_created_content": xboxone_privilege_user_created_content,
	    "xboxone_privilege_multiplayer_sessions": xboxone_privilege_multiplayer_sessions,
	    "xboxone_privilege_sessions": xboxone_privilege_sessions,
	    "xboxone_privilege_fitness_upload": xboxone_privilege_fitness_upload,
	    "xboxone_privilege_result_aborted": xboxone_privilege_result_aborted,
	    "xboxone_privilege_result_banned": xboxone_privilege_result_banned,
	    "xboxone_privilege_result_no_issue": xboxone_privilege_result_no_issue,
	    "xboxone_privilege_result_purchase_required": xboxone_privilege_result_purchase_required,
	    "xboxone_privilege_result_restricted": xboxone_privilege_result_restricted,
	    "xboxone_privilege_result_unknown": xboxone_privilege_result_unknown,
	    "xboxone_match_visibility_usetemplate": xboxone_match_visibility_usetemplate,
	    "xboxone_match_visibility_open": xboxone_match_visibility_open,
	    "xboxone_match_visibility_private": xboxone_match_visibility_private,
	    "xboxone_chat_relationship_none": xboxone_chat_relationship_none,
	    "xboxone_chat_relationship_receive_all": xboxone_chat_relationship_receive_all,
	    "xboxone_chat_relationship_receive_audio": xboxone_chat_relationship_receive_audio,
	    "xboxone_chat_relationship_receive_text": xboxone_chat_relationship_receive_text,
	    "xboxone_chat_relationship_send_all": xboxone_chat_relationship_send_all,
	    "xboxone_chat_relationship_send_and_receive_all": xboxone_chat_relationship_send_and_receive_all,
	    "xboxone_chat_relationship_send_microphone_audio": xboxone_chat_relationship_send_microphone_audio,
	    "xboxone_chat_relationship_send_text": xboxone_chat_relationship_send_text,
	    "xboxone_chat_relationship_send_text_to_speech_audio": xboxone_chat_relationship_send_text_to_speech_audio,
	    "xboxone_achievement_already_unlocked": xboxone_achievement_already_unlocked,
	    "xboxone_achievement_already_unlocked": xboxone_achievement_already_unlocked,
	    "xboxone_achievement_progress_unknown": xboxone_achievement_progress_unknown,
	    "xboxone_achievement_progress_unlocked": xboxone_achievement_progress_unlocked,
	    "xboxone_achievement_progress_notstarted": xboxone_achievement_progress_notstarted,
	    "xboxone_achievement_progress_inprogress": xboxone_achievement_progress_inprogress,
	    "e_ms_iap_ProductKind_None": e_ms_iap_ProductKind_None,
	    "e_ms_iap_ProductKind_Consumable": e_ms_iap_ProductKind_Consumable,
	    "e_ms_iap_ProductKind_Durable": e_ms_iap_ProductKind_Durable,
	    "e_ms_iap_ProductKind_Game": e_ms_iap_ProductKind_Game,
	    "e_ms_iap_ProductKind_Pass": e_ms_iap_ProductKind_Pass,
	    "e_ms_iap_ProductKind_UnmanagedConsumable": e_ms_iap_ProductKind_UnmanagedConsumable,
	    "e_ms_iap_PackageKind_Game": e_ms_iap_PackageKind_Game,
	    "e_ms_iap_PackageKind_Content": e_ms_iap_PackageKind_Content,
	    "e_ms_iap_PackageEnumerationScope_ThisOnly": e_ms_iap_PackageEnumerationScope_ThisOnly,
	    "e_ms_iap_PackageEnumerationScope_ThisAndRelated": e_ms_iap_PackageEnumerationScope_ThisAndRelated,
	    "device_gdk_unknown": device_gdk_unknown,
	    "device_gdk_pc": device_gdk_pc,
	    "device_gdk_xboxone": device_gdk_xboxone,
	    "device_gdk_xboxones": device_gdk_xboxones,
	    "device_gdk_xboxonex": device_gdk_xboxonex,
	    "device_gdk_xboxonexdevkit": device_gdk_xboxonexdevkit,
	    "device_gdk_xboxseriess": device_gdk_xboxseriess,
	    "device_gdk_xboxseriesx": device_gdk_xboxseriesx,
	    "device_gdk_xboxseriesdevkit": device_gdk_xboxseriesdevkit,
	    "xboxlive_fileerror_noerror": xboxlive_fileerror_noerror,
	    "xboxlive_fileerror_outofmemory": xboxlive_fileerror_outofmemory,
	    "xboxlive_fileerror_usernotfound": xboxlive_fileerror_usernotfound,
	    "xboxlive_fileerror_unknownerror": xboxlive_fileerror_unknownerror,
	    "xboxlive_fileerror_cantopenfile": xboxlive_fileerror_cantopenfile,
	    "xboxlive_fileerror_blobnotfound": xboxlive_fileerror_blobnotfound,
	    "xboxlive_fileerror_containernotinsync": xboxlive_fileerror_containernotinsync,
	    "xboxlive_fileerror_containersyncfailed": xboxlive_fileerror_containersyncfailed,
	    "xboxlive_fileerror_invalidcontainername": xboxlive_fileerror_invalidcontainername,
	    "xboxlive_fileerror_noaccess": xboxlive_fileerror_noaccess,
	    "xboxlive_fileerror_noxboxliveinfo": xboxlive_fileerror_noxboxliveinfo,
	    "xboxlive_fileerror_outoflocalstorage": xboxlive_fileerror_outoflocalstorage,
	    "xboxlive_fileerror_providedbuffertoosmall": xboxlive_fileerror_providedbuffertoosmall,
	    "xboxlive_fileerror_quotaexceeded": xboxlive_fileerror_quotaexceeded,
	    "xboxlive_fileerror_updatetoobig": xboxlive_fileerror_updatetoobig,
	    "xboxlive_fileerror_usercanceled": xboxlive_fileerror_usercanceled,
	    "xboxlive_gamerpic_small": xboxlive_gamerpic_small,
	    "xboxlive_gamerpic_medium": xboxlive_gamerpic_medium,
	    "xboxlive_gamerpic_large": xboxlive_gamerpic_large,
	    "xboxlive_agegroup_unknown": xboxlive_agegroup_unknown,
	    "xboxlive_agegroup_child": xboxlive_agegroup_child,
	    "xboxlive_agegroup_teen": xboxlive_agegroup_teen,
	    "xboxlive_agegroup_adult": xboxlive_agegroup_adult,
	    "xboxlive_chat_relationship_none": xboxlive_chat_relationship_none,
	    "xboxlive_chat_relationship_receive_all": xboxlive_chat_relationship_receive_all,
	    "xboxlive_chat_relationship_receive_audio": xboxlive_chat_relationship_receive_audio,
	    "xboxlive_chat_relationship_receive_text": xboxlive_chat_relationship_receive_text,
	    "xboxlive_chat_relationship_send_all": xboxlive_chat_relationship_send_all,
	    "xboxlive_chat_relationship_send_and_receive_all": xboxlive_chat_relationship_send_and_receive_all,
	    "xboxlive_chat_relationship_send_microphone_audio": xboxlive_chat_relationship_send_microphone_audio,
	    "xboxlive_chat_relationship_send_text": xboxlive_chat_relationship_send_text,
	    "xboxlive_chat_relationship_send_text_to_speech_audio": xboxlive_chat_relationship_send_text_to_speech_audio,
	    "uwp_privilege_internet_browsing": uwp_privilege_internet_browsing,
	    "uwp_privilege_social_network_sharing": uwp_privilege_social_network_sharing,
	    "uwp_privilege_share_kinect_content": uwp_privilege_share_kinect_content,
	    "uwp_privilege_video_communications": uwp_privilege_video_communications,
	    "uwp_privilege_communications": uwp_privilege_communications,
	    "uwp_privilege_user_created_content": uwp_privilege_user_created_content,
	    "uwp_privilege_multiplayer_sessions": uwp_privilege_multiplayer_sessions,
	    "uwp_privilege_sessions": uwp_privilege_sessions,
	    "uwp_privilege_fitness_upload": uwp_privilege_fitness_upload,
	    "uwp_privilege_result_aborted": uwp_privilege_result_aborted,
	    "uwp_privilege_result_banned": uwp_privilege_result_banned,
	    "uwp_privilege_result_no_issue": uwp_privilege_result_no_issue,
	    "uwp_privilege_result_purchase_required": uwp_privilege_result_purchase_required,
	    "uwp_privilege_result_restricted": uwp_privilege_result_restricted,
	    "xboxlive_match_visibility_usetemplate": xboxlive_match_visibility_usetemplate,
	    "xboxlive_match_visibility_open": xboxlive_match_visibility_open,
	    "xboxlive_match_visibility_private": xboxlive_match_visibility_private,
	    "xboxlive_achievement_already_unlocked": xboxlive_achievement_already_unlocked,
	    "xboxlive_achievement_progress_unknown": xboxlive_achievement_progress_unknown,
	    "xboxlive_achievement_progress_unlocked": xboxlive_achievement_progress_unlocked,
	    "xboxlive_achievement_progress_notstarted": xboxlive_achievement_progress_notstarted,
	    "xboxlive_achievement_progress_inprogress": xboxlive_achievement_progress_inprogress,
	    "PSN_LEADERBOARD_SCORE_MSG": PSN_LEADERBOARD_SCORE_MSG,
	    "PSN_LEADERBOARD_SCORE_RANGE_MSG": PSN_LEADERBOARD_SCORE_RANGE_MSG,
	    "PSN_LEADERBOARD_FRIENDS_SCORES_MSG": PSN_LEADERBOARD_FRIENDS_SCORES_MSG,
	    "PSN_LEADERBOARD_SCORE_POSTED_MSG": PSN_LEADERBOARD_SCORE_POSTED_MSG,
	    "PSN_WEBAPI_MSG": PSN_WEBAPI_MSG,
	    "PSN_TROPHY_INFO_MSG": PSN_TROPHY_INFO_MSG,
	    "PSN_TROPHY_UNLOCKED_MSG": PSN_TROPHY_UNLOCKED_MSG,
	    "PSN_TROPHY_UNLOCK_STATE": PSN_TROPHY_UNLOCK_STATE,
	    "PSN_TROPHY_UNLOCK_CALLBACK": PSN_TROPHY_UNLOCK_CALLBACK,
	    "MATCHMAKING_CONNECTION": MATCHMAKING_CONNECTION,
	    "MATCHMAKING_SESSION": MATCHMAKING_SESSION,
	    "MATCHMAKING_INVITATION": MATCHMAKING_INVITATION,
	    "MATCHMAKING_PLAY_TOGETHER": MATCHMAKING_PLAY_TOGETHER,
	    "PSN_SERVICE_STATE": PSN_SERVICE_STATE,
	    "MATCHMAKING_OPERATOR_EQUAL": MATCHMAKING_OPERATOR_EQUAL,
	    "MATCHMAKING_OPERATOR_NOTEQUAL": MATCHMAKING_OPERATOR_NOTEQUAL,
	    "MATCHMAKING_OPERATOR_LESSTHAN": MATCHMAKING_OPERATOR_LESSTHAN,
	    "MATCHMAKING_OPERATOR_LESSTHANOREQUAL": MATCHMAKING_OPERATOR_LESSTHANOREQUAL,
	    "MATCHMAKING_OPERATOR_GREATERTHAN": MATCHMAKING_OPERATOR_GREATERTHAN,
	    "MATCHMAKING_OPERATOR_GREATERTHANOREQUAL": MATCHMAKING_OPERATOR_GREATERTHANOREQUAL,
	    "switch_controller_joycon_holdtype_vertical": switch_controller_joycon_holdtype_vertical,
	    "switch_controller_joycon_holdtype_horizontal": switch_controller_joycon_holdtype_horizontal,
	    "switch_controller_handheld": switch_controller_handheld,
	    "switch_controller_pro_controller": switch_controller_pro_controller,
	    "switch_controller_joycon_dual": switch_controller_joycon_dual,
	    "switch_controller_joycon_left": switch_controller_joycon_left,
	    "switch_controller_joycon_right": switch_controller_joycon_right,
	    "switch_controller_joycon_assignment_dual": switch_controller_joycon_assignment_dual,
	    "switch_controller_joycon_assignment_single": switch_controller_joycon_assignment_single,
	    "switch_controller_motor_single": switch_controller_motor_single,
	    "switch_controller_motor_left": switch_controller_motor_left,
	    "switch_controller_motor_right": switch_controller_motor_right,
	    "switch_theme_default": switch_theme_default,
	    "switch_theme_user": switch_theme_user,
	    "switch_theme_white": switch_theme_white,
	    "switch_theme_black": switch_theme_black,
	    "switch_screenshot_rotation_none": switch_screenshot_rotation_none,
	    "switch_screenshot_rotation_90": switch_screenshot_rotation_90,
	    "switch_screenshot_rotation_180": switch_screenshot_rotation_180,
	    "switch_screenshot_rotation_270": switch_screenshot_rotation_270,
	    "switch_controller_axis_x": switch_controller_axis_x,
	    "switch_controller_axis_y": switch_controller_axis_y,
	    "switch_controller_axis_z": switch_controller_axis_z,
	    "switch_irsensor_light_target_all": switch_irsensor_light_target_all,
	    "switch_irsensor_light_target_far": switch_irsensor_light_target_far,
	    "switch_irsensor_light_target_near": switch_irsensor_light_target_near,
	    "switch_irsensor_light_target_none": switch_irsensor_light_target_none,
	    "switch_irsensor_ambient_noise_low": switch_irsensor_ambient_noise_low,
	    "switch_irsensor_ambient_noise_middle": switch_irsensor_ambient_noise_middle,
	    "switch_irsensor_ambient_noise_high": switch_irsensor_ambient_noise_high,
	    "switch_irsensor_ambient_noise_unknown": switch_irsensor_ambient_noise_unknown,
	    "switch_irsensor_mode_none": switch_irsensor_mode_none,
	    "switch_irsensor_mode_moment": switch_irsensor_mode_moment,
	    "switch_irsensor_mode_cluster": switch_irsensor_mode_cluster,
	    "switch_irsensor_mode_image": switch_irsensor_mode_image,
	    "switch_irsensor_mode_hand": switch_irsensor_mode_hand,
	    "switch_irsensor_moment_preprocess_binarize": switch_irsensor_moment_preprocess_binarize,
	    "switch_irsensor_moment_preprocess_cutoff": switch_irsensor_moment_preprocess_cutoff,
	    "switch_irsensor_hand_mode_none": switch_irsensor_hand_mode_none,
	    "switch_irsensor_hand_mode_silhouette": switch_irsensor_hand_mode_silhouette,
	    "switch_irsensor_hand_mode_image": switch_irsensor_hand_mode_image,
	    "switch_irsensor_hand_mode_silhouette_and_image": switch_irsensor_hand_mode_silhouette_and_image,
	    "switch_irsensor_hand_mode_silhouette_only": switch_irsensor_hand_mode_silhouette_only,
	    "switch_irsensor_image_format_qvga": switch_irsensor_image_format_qvga,
	    "switch_irsensor_image_format_qqvga": switch_irsensor_image_format_qqvga,
	    "switch_irsensor_image_format_qqqvga": switch_irsensor_image_format_qqqvga,
	    "switch_irsensor_image_format_320x240": switch_irsensor_image_format_320x240,
	    "switch_irsensor_image_format_160x120": switch_irsensor_image_format_160x120,
	    "switch_irsensor_image_format_80x60": switch_irsensor_image_format_80x60,
	    "switch_irsensor_image_format_40x30": switch_irsensor_image_format_40x30,
	    "switch_irsensor_image_format_20x15": switch_irsensor_image_format_20x15,
	    "switch_irsensor_hand_chirality_left": switch_irsensor_hand_chirality_left,
	    "switch_irsensor_hand_chirality_right": switch_irsensor_hand_chirality_right,
	    "switch_irsensor_hand_chirality_unknown": switch_irsensor_hand_chirality_unknown,
	    "switch_irsensor_hand_finger_thumb": switch_irsensor_hand_finger_thumb,
	    "switch_irsensor_hand_finger_index": switch_irsensor_hand_finger_index,
	    "switch_irsensor_hand_finger_middle": switch_irsensor_hand_finger_middle,
	    "switch_irsensor_hand_finger_ring": switch_irsensor_hand_finger_ring,
	    "switch_irsensor_hand_finger_little": switch_irsensor_hand_finger_little,
	    "switch_irsensor_hand_finger_count": switch_irsensor_hand_finger_count,
	    "switch_irsensor_hand_touching_index_middle": switch_irsensor_hand_touching_index_middle,
	    "switch_irsensor_hand_touching_middle_ring": switch_irsensor_hand_touching_middle_ring,
	    "switch_irsensor_hand_touching_ring_little": switch_irsensor_hand_touching_ring_little,
	    "switch_irsensor_hand_touching_count": switch_irsensor_hand_touching_count,
	    "switch_controller_handheld_activation_dual": switch_controller_handheld_activation_dual,
	    "switch_controller_handheld_activation_single": switch_controller_handheld_activation_single,
	    "switch_controller_handheld_activation_none": switch_controller_handheld_activation_none,
	    "switch_cpu_boost_mode_normal": switch_cpu_boost_mode_normal,
	    "switch_cpu_boost_mode_fastload": switch_cpu_boost_mode_fastload,
	    "switch_controller_gyro_zero_drift_loose": switch_controller_gyro_zero_drift_loose,
	    "switch_controller_gyro_zero_drift_standard": switch_controller_gyro_zero_drift_standard,
	    "switch_controller_gyro_zero_drift_tight": switch_controller_gyro_zero_drift_tight,
	    "switch_performance_mode_invalid": switch_performance_mode_invalid,
	    "switch_performance_mode_normal": switch_performance_mode_normal,
	    "switch_performance_mode_boost": switch_performance_mode_boost,
	    "switch_performance_config_invalid": switch_performance_config_invalid,
	    "switch_performance_config_Cpu1020MhzGpu768MhzEmc1600Mhz": switch_performance_config_Cpu1020MhzGpu768MhzEmc1600Mhz,
	    "switch_performance_config_Cpu1020MhzGpu307MhzEmc1331Mhz": switch_performance_config_Cpu1020MhzGpu307MhzEmc1331Mhz,
	    "switch_performance_config_Cpu1020MhzGpu384MhzEmc1331Mhz": switch_performance_config_Cpu1020MhzGpu384MhzEmc1331Mhz,
	    "switch_matchmaking_type_anybody": switch_matchmaking_type_anybody,
	    "switch_matchmaking_type_friends": switch_matchmaking_type_friends,
	    "switch_leaderboard_type_user": switch_leaderboard_type_user,
	    "switch_leaderboard_type_near": switch_leaderboard_type_near,
	    "switch_leaderboard_type_anybody": switch_leaderboard_type_anybody,
	    "switch_leaderboard_type_friends": switch_leaderboard_type_friends,
	    "SWITCH_LEADERBOARD_SCORE_RANGE_MSG": SWITCH_LEADERBOARD_SCORE_RANGE_MSG,
	    "SWITCH_LEADERBOARD_SCORE_POSTED_MSG": SWITCH_LEADERBOARD_SCORE_POSTED_MSG,
	    "SWITCH_LEADERBOARD_COMMON_DATA_POSTED_MSG": SWITCH_LEADERBOARD_COMMON_DATA_POSTED_MSG,
	    "switch_language_japanese": switch_language_japanese,
	    "switch_language_americanenglish": switch_language_americanenglish,
	    "switch_language_french": switch_language_french,
	    "switch_language_german": switch_language_german,
	    "switch_language_italian": switch_language_italian,
	    "switch_language_spanish": switch_language_spanish,
	    "switch_language_chinese": switch_language_chinese,
	    "switch_language_korean": switch_language_korean,
	    "switch_language_dutch": switch_language_dutch,
	    "switch_language_portuguese": switch_language_portuguese,
	    "switch_language_russian": switch_language_russian,
	    "switch_language_taiwanese": switch_language_taiwanese,
	    "switch_language_britishenglish": switch_language_britishenglish,
	    "switch_language_canadianfrench": switch_language_canadianfrench,
	    "switch_language_latinamericanspanish": switch_language_latinamericanspanish,
	    "switch_language_simplifiedchinese": switch_language_simplifiedchinese,
	    "switch_language_traditionalchinese": switch_language_traditionalchinese,
	    "SWITCH_GAMESERVER": SWITCH_GAMESERVER,*/
	    "path_action_stop": path_action_stop,
	    "path_action_restart": path_action_restart,
	    "path_action_continue": path_action_continue,
	    "path_action_reverse": path_action_reverse,
	    /*"vbm_fast": vbm_fast,
	    "vbm_compatible": vbm_compatible,
	    "vbm_most_compatible": vbm_most_compatible,*/
	    "tm_sleep": tm_sleep,
	    "tm_countvsyncs": tm_countvsyncs,
	    "tm_systemtiming": tm_systemtiming,
	    "layerelementtype_undefined": layerelementtype_undefined,
	    "layerelementtype_background": layerelementtype_background,
	    "layerelementtype_instance": layerelementtype_instance,
	    "layerelementtype_oldtilemap": layerelementtype_oldtilemap,
	    "layerelementtype_sprite": layerelementtype_sprite,
	    "layerelementtype_tilemap": layerelementtype_tilemap,
	    "layerelementtype_particlesystem": layerelementtype_particlesystem,
	    "layerelementtype_tile": layerelementtype_tile,
	    "layerelementtype_sequence": layerelementtype_sequence,
	    "layerelementtype_text": layerelementtype_text,
	    "tile_rotate": tile_rotate,
	    "tile_flip": tile_flip,
	    "tile_mirror": tile_mirror,
	    "tile_index_mask": tile_index_mask,
	    "textalign_left": textalign_left,
	    "textalign_center": textalign_center,
	    "textalign_right": textalign_right,
	    "textalign_justify": textalign_justify,
	    "textalign_top": textalign_top,
	    "textalign_middle": textalign_middle,
	    "textalign_bottom": textalign_bottom,
	    "seqplay_oneshot": seqplay_oneshot,
	    "seqplay_loop": seqplay_loop,
	    "seqplay_pingpong": seqplay_pingpong,
	    "seqdir_right": seqdir_right,
	    "seqdir_left": seqdir_left,
	    "seqtracktype_graphic": seqtracktype_graphic,
	    "seqtracktype_audio": seqtracktype_audio,
	    "seqtracktype_real": seqtracktype_real,
	    "seqtracktype_color": seqtracktype_color,
	    "seqtracktype_colour": seqtracktype_colour,
	    "seqtracktype_bool": seqtracktype_bool,
	    "seqtracktype_string": seqtracktype_string,
	    "seqtracktype_sequence": seqtracktype_sequence,
	    "seqtracktype_clipmask": seqtracktype_clipmask,
	    "seqtracktype_clipmask_mask": seqtracktype_clipmask_mask,
	    "seqtracktype_clipmask_subject": seqtracktype_clipmask_subject,
	    "seqtracktype_group": seqtracktype_group,
	    "seqtracktype_empty": seqtracktype_empty,
	    "seqtracktype_spriteframes": seqtracktype_spriteframes,
	    "seqtracktype_instance": seqtracktype_instance,
	    "seqtracktype_message": seqtracktype_message,
	    "seqtracktype_moment": seqtracktype_moment,
	    "seqtracktype_text": seqtracktype_text,
	    "seqtracktype_particlesystem": seqtracktype_particlesystem,
	    "seqtracktype_audioeffect": seqtracktype_audioeffect,
	    "animcurvetype_linear": animcurvetype_linear,
	    "animcurvetype_catmullrom": animcurvetype_catmullrom,
	    "animcurvetype_bezier": animcurvetype_bezier,
	    "seqaudiokey_loop": seqaudiokey_loop,
	    "seqaudiokey_oneshot": seqaudiokey_oneshot,
	    "seqtextkey_left": seqtextkey_left,
	    "seqtextkey_center": seqtextkey_center,
	    "seqtextkey_right": seqtextkey_right,
	    "seqtextkey_justify": seqtextkey_justify,
	    "seqtextkey_top": seqtextkey_top,
	    "seqtextkey_middle": seqtextkey_middle,
	    "seqtextkey_bottom": seqtextkey_bottom,
	    "seqinterpolation_assign": seqinterpolation_assign,
	    "seqinterpolation_lerp": seqinterpolation_lerp,
	    "cmpfunc_never": cmpfunc_never,
	    "cmpfunc_less": cmpfunc_less,
	    "cmpfunc_equal": cmpfunc_equal,
	    "cmpfunc_lessequal": cmpfunc_lessequal,
	    "cmpfunc_greater": cmpfunc_greater,
	    "cmpfunc_notequal": cmpfunc_notequal,
	    "cmpfunc_greaterequal": cmpfunc_greaterequal,
	    "cmpfunc_always": cmpfunc_always,
	    "stencilop_keep": stencilop_keep,
	    "stencilop_zero": stencilop_zero,
	    "stencilop_replace": stencilop_replace,
	    "stencilop_incr_wrap": stencilop_incr_wrap,
	    "stencilop_decr_wrap": stencilop_decr_wrap,
	    "stencilop_invert": stencilop_invert,
	    "stencilop_incr": stencilop_incr,
	    "stencilop_decr": stencilop_decr,
	    "cull_noculling": cull_noculling,
	    "cull_clockwise": cull_clockwise,
	    "cull_counterclockwise": cull_counterclockwise,
	    "lighttype_dir": lighttype_dir,
	    "lighttype_point": lighttype_point,
	    "bboxmode_automatic": bboxmode_automatic,
	    "bboxmode_fullimage": bboxmode_fullimage,
	    "bboxmode_manual": bboxmode_manual,
	    "bboxkind_precise": bboxkind_precise,
	    "bboxkind_rectangular": bboxkind_rectangular,
	    "bboxkind_ellipse": bboxkind_ellipse,
	    "bboxkind_diamond": bboxkind_diamond,
	    "bboxkind_spine": bboxkind_spine,
	    "kbv_type_default": kbv_type_default,
	    "kbv_type_ascii": kbv_type_ascii,
	    "kbv_type_url": kbv_type_url,
	    "kbv_type_email": kbv_type_email,
	    "kbv_type_numbers": kbv_type_numbers,
	    "kbv_type_phone": kbv_type_phone,
	    "kbv_type_phone_name": kbv_type_phone_name,
	    "kbv_returnkey_default": kbv_returnkey_default,
	    "kbv_returnkey_go": kbv_returnkey_go,
	    "kbv_returnkey_google": kbv_returnkey_google,
	    "kbv_returnkey_join": kbv_returnkey_join,
	    "kbv_returnkey_next": kbv_returnkey_next,
	    "kbv_returnkey_route": kbv_returnkey_route,
	    "kbv_returnkey_search": kbv_returnkey_search,
	    "kbv_returnkey_send": kbv_returnkey_send,
	    "kbv_returnkey_yahoo": kbv_returnkey_yahoo,
	    "kbv_returnkey_done": kbv_returnkey_done,
	    "kbv_returnkey_continue": kbv_returnkey_continue,
	    "kbv_returnkey_emergency": kbv_returnkey_emergency,
	    "kbv_autocapitalize_none": kbv_autocapitalize_none,
	    "kbv_autocapitalize_words": kbv_autocapitalize_words,
	    "kbv_autocapitalize_sentences": kbv_autocapitalize_sentences,
	    "kbv_autocapitalize_characters": kbv_autocapitalize_characters,
	    "os_permission_denied_dont_request": os_permission_denied_dont_request,
	    "os_permission_denied": os_permission_denied,
	    "os_permission_granted": os_permission_granted,
	    "nineslice_left": nineslice_left,
	    "nineslice_top": nineslice_top,
	    "nineslice_right": nineslice_right,
	    "nineslice_bottom": nineslice_bottom,
	    "nineslice_centre": nineslice_centre,
	    "nineslice_center": nineslice_center,
	    "nineslice_stretch": nineslice_stretch,
	    "nineslice_repeat": nineslice_repeat,
	    "nineslice_mirror": nineslice_mirror,
	    "nineslice_blank": nineslice_blank,
	    "nineslice_hide": nineslice_hide,
	    "texturegroup_status_unloaded": texturegroup_status_unloaded,
	    "texturegroup_status_loading": texturegroup_status_loading,
	    "texturegroup_status_loaded": texturegroup_status_loaded,
	    "texturegroup_status_fetched": texturegroup_status_fetched,
	    "surface_rgba8unorm": surface_rgba8unorm,
	    "surface_r16float": surface_r16float,
	    "surface_r32float": surface_r32float,
	    "surface_rgba4unorm": surface_rgba4unorm,
	    "surface_r8unorm": surface_r8unorm,
	    "surface_rg8unorm": surface_rg8unorm,
	    "surface_rgba16float": surface_rgba16float,
	    "surface_rgba32float": surface_rgba32float,
	    "os_type": os_type,
	    "os_browser": os_browser,
	    "rollback_connected_to_peer": rollback_connected_to_peer,
	    "rollback_synchronizing_with_peer": rollback_synchronizing_with_peer,
	    "rollback_synchronized_with_peer": rollback_synchronized_with_peer,
	    "rollback_disconnected_from_peer": rollback_disconnected_from_peer,
	    "rollback_game_interrupted": rollback_game_interrupted,
	    "rollback_game_resumed": rollback_game_resumed,
	    "rollback_game_full": rollback_game_full,
	    "rollback_game_info": rollback_game_info,
	    "rollback_connection_rejected": rollback_connection_rejected,
	    "rollback_protocol_rejected": rollback_protocol_rejected,
	    "rollback_end_game": rollback_end_game,
	    "rollback_chat_message": rollback_chat_message,
	    "rollback_player_prefs": rollback_player_prefs,
	    "rollback_high_latency": rollback_high_latency,
	    "rollback_connect_info": rollback_connect_info,
	    "rollback_connect_error": rollback_connect_error,
        "GM_build_date": GM_build_date,
        "GM_version": GM_version,
        "GM_runtime_version": GM_runtime_version,
        "GM_built_type": GM_build_type,
	}
}
#endregion

#region overrides
// preparations
function __gml_method_get_self_real(fn)
{
	static _method_get_self = asset_get_index("method_get_self");
	return _method_get_self(fn);
}

function __gml_method_real(a, b)
{
    static _method = asset_get_index("method");
    return _method(a, b);
}

function __gml_static_get_real(a)
{
    static _static_get = asset_get_index("static_get");
    return _static_get(a);
}

function __gml_is_gmlfunc_self(this_self)
{
	return is_struct(this_self) && struct_exists(this_self, gml_func_sig)
}

#macro __args_toarray  var _args = []; for (var i = 0; i < argument_count; i++) array_push(_args, argument[i])
#macro __args_toarray1 var _args = []; for (var i = 1; i < argument_count; i++) array_push(_args, argument[i])
function __gml_script_execute_ext_real()
{
    static _exec_ext = asset_get_index("script_execute_ext")
    __args_toarray
    
    return _exec_ext(_exec_ext, _args)
}

// method
#macro method __gml_method

function __gml_method(new_self, fn)
{
	var this_self = __gml_method_get_self_real(fn);
	if __gml_is_gmlfunc_self(this_self)
	{
		// it's a function we made
        gml_vm_func_setscope(this_self, new_self, other)
		return fn;
	}
	
	return __gml_method_real(new_self, fn);
}

// method_get_self
#macro method_get_self __gml_method_get_self

function __gml_method_get_self(fn)
{
	var this_self = __gml_method_get_self_real(fn);
	
	if __gml_is_gmlfunc_self(this_self)
		return this_self._self;
		
	return this_self;
}

// static_get
#macro static_get __gml_static_get

function __gml_static_get(objet)
{
	// WHY ARE METHODS STRUCTS
	if is_struct(objet) && !is_method(objet)
		return __gml_static_get_real(objet);
		
	var this_self = __gml_method_get_self_real(objet);
	if __gml_is_gmlfunc_self(this_self)
    {
        return this_self.statics;
    }
	
	return __gml_static_get_real(objet);
}

// script_execute
#macro script_execute __gml_script_execute

function __gml_script_execute(scr)
{
    __args_toarray1
    
    var this_self = __gml_method_get_self_real(scr)
    if __gml_is_gmlfunc_self(this_self) with this_self
        return __gml_script_execute_ext_real(scr, _args)
    
    return __gml_script_execute_ext_real(scr, _args)
}

// script_execute_ext
#macro script_execute_ext __gml_script_execute_ext

function __gml_script_execute_ext(scr)
{
    __args_toarray
    
    var this_self = __gml_method_get_self_real(scr)
    if __gml_is_gmlfunc_self(this_self) with this_self
        return __gml_script_execute_ext_real(__gml_script_execute_ext_real, _args)
    
    return __gml_script_execute_ext_real(__gml_script_execute_ext_real, _args)
}
#endregion

function __gml_call(meth, args, is_constructor = false)
{
    // special handling
    var this_self = __gml_method_get_self_real(meth)
    if __gml_is_gmlfunc_self(this_self)
    {
        var __s = self, __o = other;
        array_insert(args, 0, { self: __s, other: __o, "_@callinfo": true })
    }
    
    if (!is_constructor)
    {
    	return method_call(meth, args)
    }
    else
    {
    	var ins = {}
    	
    	// basically, I can't find a way to call constructor functions except for whatever this is
    	// if they have a self bound to them, it's usually shifted to the 'other' since the 'self' becomes
    	// the current struct that's being constructed.
    	// We have to make an unbound copy and properly arrange things ourselves.
    	var construct_self = __gml_method_get_self_real(meth)
    	var naked_meth = __gml_method_real(undefined, meth)
    	with construct_self
    	{
	    	with ins
	    		method_call(naked_meth, args)
    	}
    	return ins;
    }
}

function gml_vm_builtin(varname)
{
    static found = false;
    if varname == "global"
        return global;
    
    found = true;
    
    // overrides
    var override = struct_get(__gml.vm_overrides, varname)
    if !is_undefined(override)
        return override;
    
    // try resolve assets
    var indx = struct_get(__gml.vm_cached_assets, varname)
    if !is_undefined(indx)
        return int64(indx)
    
    // and constants
    if struct_exists(__gml.vm_constants, varname)
        return struct_get(__gml.vm_constants, varname);
    
    // last resort
    var asset = asset_get_index(varname)
    if asset != -1
        return int64(asset);
    
    found = false;
}

#region constructs
function gmlVMScript() constructor
{
    self.blacklisted = {}

    static AddBlacklist = function ()
    {
    	for (var i = 0; i < argument_count; i++)
    	{
    		var arg = argument[i]
    		if script_exists(arg) || object_exists(arg)
    			self.blacklisted[$ int64(arg)] = true;
    		else
    			throw $"Cannot blacklist value: {arg}. Must be a script or object.";
    	}
    }
    
    static ClearBlacklist = function ()
    {
    	self.blacklisted = {}
    }
    
    static IsBlacklisted = function (asset_index)
    {
    	// don't blacklist normal numbers, normal assets are also returned as int64s
    	if !is_int64(asset_index)
    		return false;
    	
    	return struct_names_count(self.blacklisted) > 0 && (self.blacklisted[$ asset_index] ?? false);
    }
    
    static EnsureAllowed = function (value)
    {
    	if self.IsBlacklisted(value)
    		throw $"Asset is blacklisted!"
    		
    	return value;
    }
    
    self.function_table = []
}

function gmlVMContext(script, instance, inst_other, gmfunc = "<gml.gml>") constructor 
{
    if is_undefined(script)
        throw "Can't create context with no script provided to it"
    
    if !is_instanceof(script, gmlVMScript)
        throw "Script isn't a gmlVMScript"
    
    self.script = script;
    self.scope = instance
    
    if !__gml_vm_is_valid_scope(instance)
    	throw "Invalid self.scope"
    
    self.scope_other = inst_other;
    
    if is_undefined(self.scope) || is_undefined(self.scope_other)
        throw "gmlVMContext must be initialized fully with both the 'self' and 'other' filled in"
    
    self.readonly = {}
    self.statics = {}
    
    self.locals = {}
    
    self.in_constructor = false;
    
    self.gm_function = gmfunc
    
    static MarkConstructor = function ()
    {
        self.in_constructor = true;
        return self;
    }
    
    // functions, not methods
    self.functions = {}
    
    static SetFunc = function (name, func)
    {
        if struct_exists(self.functions, name)
        	return;
        	
        self.functions[$ name] = func;
    }
    static GetFunc = function (name)
    {
        return self.functions[$ name];
    }
    static HasFunc = function (name)
    {
    	return struct_exists(self.functions, name)
    }
    
    static Extend = function (old_ctx)
    {
        if !is_instanceof(old_ctx, gmlVMContext)
            throw "Can't extend context without a context"
        
        self.locals = old_ctx.locals;
        self.statics = old_ctx.statics;
        self.functions = old_ctx.functions;
        return self;
    }
    
    static FindVarScope = function (v)
    {
    	if struct_exists(self.locals, v) return self.locals
        if struct_exists(self.statics, v) return self.statics
        if struct_exists(self.readonly, v) return self.readonly
        if self.HasFunc(v) return self.functions;
        if variable_instance_exists(self.scope, v) return self.scope
        if variable_global_exists(v) return global;
        
        return undefined;
    }
    
    self.var_scope_cache = {}
    
    static GetVar = function (v, scope)
    {
    	if !variable_instance_exists(scope, v)
    		throw $"No such variable called {v}"
    		
    	return variable_instance_get(scope, v);
    }
    
    static SetVar = function (n, v, location_scope = undefined)
    {
        gml_vm_func_bind_selfscope(v, self.scope)
        
        // try assign to requested scope, else try find scope, and if it's nowhere default to the current scope
        location_scope = location_scope ?? FindVarScope(n) ?? self.scope;
        
        // can't assign readonlys (they tend to do that)
        if struct_exists(self.readonly, n) && location_scope == self.readonly
        	throw $"Can't assign to readonly variable: {n}";
        
    	variable_instance_set(location_scope, n, v)
    }
    
    static SetStaticVar = function (n, v)
    {
        // can't create static var again
        if struct_exists(self.statics, n)
            return;
        
        self.statics[$ n] = v;
    }
    
    self.SetVar("self", self.scope, self.readonly)
    self.SetVar("other", self.scope_other, self.readonly)
    self.SetVar("_GMFUNC_", self.gm_function, self.readonly)
}

function VMInterrupt(type, code = undefined) constructor 
{
    self.type = type;
    self.code = code;
}

function gmlLValue(get, set) constructor 
{
    self.Get = __gml_method_real(self, get);
    self.Set = __gml_method_real(self, set);
}
#endregion

function gml_vm_block(block, ctx)
{
    __gml.vm_last_node = block;
    
    var stats = is_array(block) ? block : block.statements
    
    if !is_array(stats)
        throw $"gml_vm_block called on not an array {stats}"
    
    for (var i = 0; i < array_length(stats); i++)
    {
        var k = __gml_vm_node(stats[i], ctx)
        if !is_undefined(k)
            return k;
    }
}

function gml_vm_returncode(vm_ret)
{
    if !is_instanceof(vm_ret, VMInterrupt)
        return vm_ret;
    
    if vm_ret.type == token_type.k_return
        return vm_ret.code;
    
    throw $"VM was not expected to return: {vm_ret}"
}

__gml.vm_last_node = undefined

function __gml_vm_node(node, ctx)
{
	__gml_profile("Stmt")
    __gml.vm_last_node = node;
    
    if is_array(node)
    {
        for (var i = 0; i < array_length(node); i++)
            __gml_vm_node(node[i], ctx)
    	__gml_endprofile("Stmt")
    }
    else
    {
    	__gml_endprofile("Stmt")
    	return node.Execute(ctx);
    }
}

function __gml_vm_is_lvalue(res)
{
	return is_instanceof(res, gmlLValue) || is_instanceof(res, gmlGreenVarNode) || is_instanceof(res, gmlGreenVarIndexNode)
}
function gml_vm_expr(node, ctx)
{
	__gml_profile("Expr")
	__gml.vm_last_node = node;
    var res = node.Execute(ctx)
    
    var value = res;
    if __gml_vm_is_lvalue(res)
        value = res.Get(ctx)
        
    if ctx.script.IsBlacklisted(value)
    	throw $"Can't fetch blacklisted value: {value}"
    	
    __gml_endprofile("Expr")
    
    return value;
}
function gml_vm_expr_lvalue(node, ctx)
{
	__gml.vm_last_node = node;
    var res = node.Execute(ctx)
    
    if !__gml_vm_is_lvalue(res)
        throw "Expected LValue"
    
    return res;
}

#region accessors
function __gml_staticchain_find(top, varname)
{
	var _chain = top;
    while !is_undefined(_chain)
    {
        var val = _chain[$ varname];
        if !is_undefined(val)
            break;
        
        _chain = static_get(_chain)
    }
    
    return _chain ?? top; // default to the top of the chain
}
function __gml_vm_access_checklegal(root, ctx)
{
    if is_struct(root) || root < 0
        return;
        
	if instance_exists(root)
		root = root.object_index
		
	// check whether the object index is actually in this room
	if !instance_exists(root)
		return;
		
	if object_exists(root) && ctx.script.IsBlacklisted(int64(root))
		throw $"Can't perform access on blacklisted instance: {root}";
}

// when accessing stuff by key, in some very very rare edge cases, -1 and -2 are passed in..
function __gml_vm_access_by_key_selfother_fix(ctx, root)
{
	if root == -1
		return ctx.scope;
	else if root == -2
		return ctx.scope_other;
		
	return root;
}

// setters
function __gml_vm_get_dot(ctx)
{
	var varname = node.index, val = undefined;
	root = __gml_vm_access_by_key_selfother_fix(ctx, root)
	
    if !variable_instance_exists(root, varname)
    {
    	// find it in the static chain
    	var found = __gml_staticchain_find(static_get(root), varname)
    	if !is_undefined(found)
    		val = found[$ varname]
    }
    else
    	val = variable_instance_get(root, varname);
    	
    if is_method(val) && method_get_self(root) == undefined && __gml_vm_is_valid_scope(root)
    {
    	val = method(root, val)
    }
	return val;
}

function __gml_vm_get_hash(ctx)
{
	if array_length(node.index) != 2
  		throw "Setting a grid element without 2 coordinates"
  		
    // grid accesses are weird
    var xx = gml_vm_expr(node.index[0], ctx), yy = gml_vm_expr(node.index[1], ctx);
    val = root[# xx, yy];
	return val;
}

function __gml_vm_get_accessor(ctx)
{
	var val, i = 0;
	
	// weirdly, theres some 2d syntax for almost any accessor
	// still dont get how much faster repeat is but ill do it ig
	// looks nicer anyway
	
	repeat array_length(node.index)
    {
        var idx = gml_vm_expr(node.index[i], ctx);
        
        root = __gml_vm_access_getter_accessor(node, root, idx, ctx)
        val = root;
        
        i++
    }
    
	return val;
}

// getters
function __gml_vm_set_dot(value, ctx)
{
	var varname = node.index;
    var set_already = false;
    	
    // some variables are in the static chain
    if !variable_instance_exists(root, varname)
    {
    	// dig them up
    	var found = __gml_staticchain_find(static_get(root), varname)
    	if struct_exists(found, varname)
    	{
    		found[$ varname] = value;
    		set_already = true;
    	}
    }
    	
    if !set_already
    {
    	// method.var syntax sets it to the static struct for some reason
    	if is_method(root)
    	{
    		var method_static = static_get(root)
    		method_static[$ varname] = value;
    	}
    	else
    		variable_instance_set(root, varname, value);
    }
	return value;
}

function __gml_vm_access_getter_accessor(node, root, idx, ctx)
{
	switch (node.how)
    {
    case token_type.qmark: root = root[? idx]; break
    case token_type.v_or: root = root[| idx]; break
    case token_type.dollar: 
    	root = __gml_vm_access_by_key_selfother_fix(ctx, root)
    	root = root[$ idx]; 
    	break
    case token_type.at: root = root[@ idx]; break
    case token_type.open_bracket: root = root[idx]; break
    default: throw "Unsupported accessor";
    }
    
    return root;
}

function __gml_vm_set_hash(value, ctx)
{
	if array_length(node.index) != 2
    	throw "Setting a grid element without 2 coordinates"
    	
    // grid accesses are weird
    var xx = gml_vm_expr(node.index[0], ctx), yy = gml_vm_expr(node.index[1], ctx);
    root[# xx, yy] = value;
	return value;
}

function __gml_vm_set_accessor(value, ctx)
{
	// leave out last element for the actual setting operation
	
	// this is faster apparently..
    var i = 0;
    repeat array_length(node.index) - 1
    	root = __gml_vm_access_getter_accessor(node, root, node.index[i++], ctx)
    		
    // actually set.
    var idx = gml_vm_expr(array_last(node.index), ctx);
        
    switch (node.how)
    {
    case token_type.qmark: root[? idx] = value; break
    case token_type.v_or: root[| idx] = value; break
    case token_type.dollar: root[$ idx] = value; break
    case token_type.at: root[@ idx] = value; break
    case token_type.open_bracket: root[idx] = value; break
    default: throw "Unsupported accessor";
    }
	return value;
}

// resolvers
function __gml_vm_get_access_func(how)
{
	switch (how)
	{
		case token_type.dot: return __gml_vm_get_dot;
		case token_type.hash: return __gml_vm_get_hash;
		default: return __gml_vm_get_accessor;
	}
}

function __gml_vm_set_access_func(how)
{
	switch (how)
	{
		case token_type.dot: return __gml_vm_set_dot;
		case token_type.hash: return __gml_vm_set_hash;
		default: return __gml_vm_set_accessor;
	}
}
#endregion

#macro gml_func_sig "__@gmlfunc"

function __gml_vm_is_valid_scope(scope)
{
	return is_struct(scope) || instance_exists(scope)
}

function gml_vm_func_bind_selfscope(func, scope)
{
    if is_method(func) && __gml_vm_is_valid_scope(scope)
    {
        var meth_self = __gml_method_get_self_real(func);
        
        if is_struct(meth_self) && struct_exists(meth_self, gml_func_sig) && !meth_self.scopes_filled
            gml_vm_func_setscope(meth_self, scope)
    }
}

function gml_vm_func_setscope(fn_self, __self)
{
    fn_self.scopes_filled = true;
    fn_self._self = __self;
    //fn_self._other = __other;
}

function __gml_vm_fun(callinfo)
{
    var fn_meta = self;
    var _self = other
    var _other = other
    var arg_offset = 0
    
    // only accept valid call infos
    if !is_undefined(callinfo) && is_struct(callinfo) && struct_exists(callinfo, "_@callinfo")
    {
        _self = callinfo.self;
        _other = callinfo.other;
        arg_offset++;
    }
    
    var base_script = fn_meta.base_ctx.script;
    
    // because the method self has the func signature bound to it
    // which trips up some stuff
    with {}
    try
    {
        var scope = _self;
        
        // for bound methods
        if fn_meta.scopes_filled
            scope = fn_meta._self;
        
        var par_statics = undefined;
        
        // constructor handling
        if fn_meta.is_constructor
        {
            // the current "self" (which is the caller) becomes other per the doc
            _other = scope;
            scope = {};
            
            // inheritance
            if !is_undefined(fn_meta.inherit_call)
            {
                var inherit_ctx = new gmlVMContext(base_script, fn_meta.base_ctx.scope, fn_meta.base_ctx.scope_other, fn_meta.name);
                
                for (var i = 0; i < array_length(fn_meta.arg_names); i++)
                    inherit_ctx.SetVar(fn_meta.arg_names[i], argument[i], inherit_ctx.readonly)
                
                // call parent
                var parent = gml_vm_expr(fn_meta.inherit_call, inherit_ctx);
                
                if !is_struct(parent)
                    throw "Can't inherit from a non-constructor!"
                
                par_statics = __gml_static_get_real(parent);
                
                gml_util_struct_copy(parent, scope) // all normal vars go up
            }
        }
        
        var ctx = new gmlVMContext(base_script, scope, _other, fn_meta.name)
        
        // retain the fact we're in a constructor
        if (fn_meta.is_constructor || fn_meta.base_ctx.in_constructor)
            ctx.MarkConstructor();
        ctx.statics = fn_meta.statics
        
        for (var i = 0; i < array_length(fn_meta.arg_names); i++)
        {
            var n = fn_meta.arg_names[i];
            var optional = fn_meta.arg_optionals[$ n];
            
            var v = argument[i + arg_offset];
            
            // try to use optional only when applicable
            if is_undefined(v)
            	v = !is_undefined(optional) ? gml_vm_expr(optional, ctx) : undefined;
            
            ctx.SetVar(n, v, ctx.locals)
        }
        
        // argument handling
        var arg_count = argument_count - arg_offset
        
        // argument is not a real array ????
        var argument_array = []
        for (var i = 0; i < arg_count; i++)
            argument_array[i] = argument[i + arg_offset];
        
        ctx.SetVar("argument", argument_array, ctx.readonly)
        ctx.SetVar("argument_count", arg_count, ctx.readonly)
        
        for (var i = 0; i <= 15; i++)
            ctx.SetVar($"argument{i}", argument[i + arg_offset], ctx.readonly);
        
        // bind to the static chain
        if fn_meta.is_constructor
        {
            var base_static = ctx.statics;
            
            if !is_undefined(par_statics)
            {
                // make sure that the static chain forms correctly
                static_set(base_static, par_statics)
            }
            // attach the rest of the chain to the current scope
            static_set(scope, base_static)
        }
        
        // actually running the code
        var _oldstatus = gml_vm.is_running;
        
        gml_vm.is_running = true;
        var res = gml_vm_block(fn_meta.block, ctx)
        gml_vm.is_running = _oldstatus;
        
        return fn_meta.is_constructor ? scope : gml_vm_returncode(res);
    }
    catch (error)
    {
    	var last_pos = !is_undefined(__gml.vm_last_node) ? __gml.vm_last_node.pos : {
            line: -1,
            column: 0
        };
        
        if !is_string(error)
            error = error.message;
        
        trace($"gml_run function {fn_meta.name}: runtime error at line {last_pos.line} column {last_pos.column}: {error}")
        
        return new gmlError(last_pos, error)
    }
}

// sort of "proxy" to running the underlying vm function
// and then dumping the return value struct into "self"
function __gml_vm_fun_construct() constructor
{
	var arg = []
    for (var i = 0; i < argument_count; i++)
        arg[i] = argument[i];
    
    with other
		var ret = method_call(__gml_vm_fun, arg)
	
	var names = struct_get_names(ret)
	for (var i = 0; i < array_length(names); i++)
	{
		var n = names[i];
		self[$ n] = ret[$ n]
	}
	
	static_set(self, __gml_static_get_real(ret))
}

function gml_vm_func_clearscope(fn_self)
{
    fn_self.scopes_filled = false;
    fn_self._self = undefined;
}

// operations
function __gml_op_add(ctx) { return gml_vm_expr(lhs, ctx) + gml_vm_expr(rhs, ctx); }
function __gml_op_sub(ctx) { return gml_vm_expr(lhs, ctx) - gml_vm_expr(rhs, ctx); }
function __gml_op_div(ctx) { return gml_vm_expr(lhs, ctx) / gml_vm_expr(rhs, ctx); }
function __gml_op_mul(ctx) { return gml_vm_expr(lhs, ctx) * gml_vm_expr(rhs, ctx); }
function __gml_op_mod(ctx) { return gml_vm_expr(lhs, ctx) % gml_vm_expr(rhs, ctx); }

function __gml_op_lt(ctx) { return gml_vm_expr(lhs, ctx) < gml_vm_expr(rhs, ctx); }
function __gml_op_gt(ctx) { return gml_vm_expr(lhs, ctx) > gml_vm_expr(rhs, ctx); }
function __gml_op_eq(ctx) { return gml_vm_expr(lhs, ctx) == gml_vm_expr(rhs, ctx); }
function __gml_op_neq(ctx) { return gml_vm_expr(lhs, ctx) != gml_vm_expr(rhs, ctx); }
function __gml_op_lte(ctx) { return gml_vm_expr(lhs, ctx) <= gml_vm_expr(rhs, ctx); }
function __gml_op_gte(ctx) { return gml_vm_expr(lhs, ctx) >= gml_vm_expr(rhs, ctx); }

function __gml_op_bit_or(ctx) { return gml_vm_expr(lhs, ctx) | gml_vm_expr(rhs, ctx); }
function __gml_op_bit_and(ctx) { return gml_vm_expr(lhs, ctx) & gml_vm_expr(rhs, ctx); }
function __gml_op_bit_xor(ctx) { return gml_vm_expr(lhs, ctx) ^ gml_vm_expr(rhs, ctx); }
function __gml_op_bit_lshift(ctx) { return gml_vm_expr(lhs, ctx) << gml_vm_expr(rhs, ctx); }
function __gml_op_bit_rshift(ctx) { return gml_vm_expr(lhs, ctx) >> gml_vm_expr(rhs, ctx); }

// shortciruiting ops
function __gml_op_and(ctx) 
{ 
    var _val = gml_vm_expr(lhs, ctx);
    if (!_val) return _val; 
    return gml_vm_expr(rhs, ctx); 
}

function __gml_op_or(ctx) 
{ 
    var _val = gml_vm_expr(lhs, ctx);
    if (_val) return _val; 
    return gml_vm_expr(rhs, ctx); 
}

function __gml_op_null(ctx) 
{ 
    var _val = gml_vm_expr(lhs, ctx);
    if (_val != undefined && _val != pointer_null) return _val; 
    return gml_vm_expr(rhs, ctx); 
}

function __gml_get_op(type)
{
    switch (type)
    {
        case token_type.plus:           return __gml_op_add;
        case token_type.minus:          return __gml_op_sub;
        case token_type.divide:         return __gml_op_div;
        case token_type.multiply:       return __gml_op_mul;
        case token_type.modulo:         return __gml_op_mod;
        case token_type.nullcoalesce:   return __gml_op_null;
        
        case token_type.lessthan:       return __gml_op_lt;
        case token_type.biggerthan:     return __gml_op_gt;
        
        case token_type.b_and:          return __gml_op_and;
        case token_type.b_or:           return __gml_op_or;
        case token_type.b_equal:        return __gml_op_eq;
        case token_type.b_lesseq:       return __gml_op_lte;
        case token_type.b_biggereq:     return __gml_op_gte;
        case token_type.b_nequal:       return __gml_op_neq;
        
        case token_type.v_or:           return __gml_op_bit_or;
        case token_type.v_and:          return __gml_op_bit_and;
        case token_type.v_xor:          return __gml_op_bit_xor;
        case token_type.bit_lshift:     return __gml_op_bit_lshift;
        case token_type.bit_rshift:     return __gml_op_bit_rshift;
        
        case token_type.equal:          return __gml_op_eq;
        
        default: throw $"__gml_get_op: unknown operator {type}"
    }
}

// security related stuff
function __gml_vm_expr_checkcall(func, values, ctx)
{
	var sc_name = script_get_name(func);
	// these functions can call methods without actually using the syntax
	// evade that
    if is(sc_name, "script_execute", "script_execute_ext", "method_call")
    {
    	var real_fn = values[0];
    	if ctx.script.IsBlacklisted(int64(real_fn))
    	{
    		throw $"Can't call blacklisted function: {script_get_name(real_fn)}"
    	}
    	
    	// recurse to check for possible nested patterns
    	__gml_vm_expr_checkcall(real_fn, array_slice(values, 1, 999), ctx)
    }
    // some people may use this as a bypass to object access blacklisting
    else if is(sc_name, "variable_instance_set", "variable_instance_get", "variable_struct_get", "variable_struct_set")
    {
    	__gml_vm_access_checklegal(values[0], ctx)
    }
}

function gmlAST(top, funcs) constructor
{
	self.top = top
	self.functions = funcs
	
	static FromNewTop = function (newtop)
	{
		var ast = new gmlAST(newtop, self.functions)
		
		return ast;
	}
}

#endregion

#region miscellaneous

// WIP
__gml.profiler = {}

function __gml_profiler_init(name)
{
	__gml.profiler[$ name] = {
		top: 0,
		calls: 0,
		time: 0
	}
}

__gml_profiler_init("GetVar")
__gml_profiler_init("Stmt")
__gml_profiler_init("Expr")
__gml_profiler_init("Access")

function __gml_profile(name)
{
	var profile = __gml.profiler[$ name]
	profile.top = current_time;
	profile.calls++;
}

function __gml_endprofile(name)
{
	var profile = __gml.profiler[$ name]
	profile.time += current_time - profile.top;
}

#endregion

#region outsider API
function gml_test(name, code, expected)
{
    var ret = gml_run(code);
    
    if (expected != ret)
    {
        trace($"FAILED: {name}")
        trace($"Got {ret}, expected {expected}")
    }
    else
    {
        trace($"PASSED: {name}")
    }
}

function gmlError(error, pos) constructor
{
	self.error = error;
	self.pos = pos;
}

function gml_is_error(returned)
{
    return is_instanceof(returned, gmlError)
}

function gml_parse(code)
{
    var consumer = new gmlStringConsumer(code);
    var tokens = new gmlTokenizer(consumer)
    
    try 
    {
        __gml.gml_enums = {}
        __gml.gml_functions = []
        __gml.gml_scopedepth = 0;
        
        var AST = gml_parse_block(tokens, true).Fold()
    }
    catch (error) 
    {
        var last_pos = tokens.next_token[2]
        trace($"gml_run: compile error at line {last_pos.line} column {last_pos.column}: {error}")
        
        return new gmlError(last_pos, error);
    }
    finally
    {
    	tokens.Dispose();
    }
    
    return new gmlAST(AST, __gml.gml_functions);
}

function gml_vm(AST, _script = undefined, _self = self, _other = other)
{
	static is_running = true;
	
	_script ??= new gmlVMScript()
	_script.function_table = AST.functions;
	
    var ctx = new gmlVMContext(_script, _self, _other)
    
    // define top level functions in this current scope
    var funcs = AST.functions
    for (var i = 0; i < array_length(funcs); i++)
    {
    	var funcnode = funcs[i]
    	
    	gml_vm_expr(funcnode, ctx) // define it
    }
    
    try
    {
    	var r = gml_vm_block(AST.top, ctx) ?? 0;
    	is_running = false;
    	
        return gml_vm_returncode(r);
    }
    catch (error)
    {
        var last_pos = !is_undefined(__gml.vm_last_node) ? __gml.vm_last_node.pos : {
            line: -1,
            column: 0
        };
        
        if !is_string(error)
            error = error.message;
        
        trace($"gml_run: runtime error at line {last_pos.line} column {last_pos.column}: {error}")
        
        is_running = false;
        return new gmlError(last_pos, error);
    }
}; gml_vm.is_running = false;

function gml_run(code, _self = self, _script = undefined)
{
    var parsed = gml_parse(code);
    
    if gml_is_error(parsed)
        return parsed;
    
    return gml_vm(parsed, _script, _self);
}

function gml_init()
{
	static initialized = false;
	if initialized
	{
		trace("gml_init() called more than once")
		return;
	}
	initialized = true;
	
	// set up overrides
	__gml.vm_overrides = {
		"method": __gml_method,
		"method_get_self": __gml_method_get_self,
		"static_get": __gml_static_get,
        "script_execute": __gml_script_execute,
        "script_execute_ext": __gml_script_execute_ext,
	}
	
	__gml_init_assets()
	__gml_init_constants()
	__gml_init_greenvar()
}
#endregion
