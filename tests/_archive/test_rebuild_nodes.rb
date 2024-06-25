# frozen_string_literal: true

require_relative 'test_helper'

class TestRebuildNodes < Minitest::Test
  include MinifyTestHelper

  # ===========================================
  # Group 1: Literals
  # Covers: char literal (?x), multi-char string, empty string, symbols (regular, space, operator),
  #   boolean (true→!!1, false→!1), nil, integers (hex, binary, underscore), floats,
  #   arrays (including empty), hashes (symbol keys, integer keys, empty, operator keys, nested),
  #   ranges (inclusive, exclusive), regex (with flags),
  #   %w word array, %i symbol array, string escape sequences (\t), hash with string keys,
  #   RationalNode, ComplexNode, SourceEncodingNode, SourceFileNode, SourceLineNode, HashNode with **splat
  # ===========================================

  def test_literals
    result = minify_at_level(<<~'RUBY', 1)

      puts "a"
      puts "hello"
      puts ""
      puts :hello.inspect
      puts :"hello world".inspect
      puts [:+, :-, :==].inspect
      puts nil
      puts true.inspect
      puts false.inspect
      puts 42
      puts -5
      puts 1_000_000
      puts 0.0
      puts 3.14
      puts 0xFF
      puts 0b1010
      puts [1, 2, 3].inspect
      puts [].inspect
      puts({a: 1, b: 2}.inspect)
      puts({1 => "one"}.inspect)
      puts({}.inspect)
      h_ops = { :== => 1, :+ => 2, :<= => 3 }
      puts h_ops[:==]
      h_nested = { a: { b: { c: 42 } } }
      puts h_nested[:a][:b][:c]
      puts (1..5).to_a.inspect
      puts (1...5).to_a.inspect
      puts /hello/.inspect
      puts /test/i.inspect
      puts /test/mx.inspect
      puts %w[foo bar baz].inspect
      puts %i[foo bar baz].inspect
      puts "tab:\there"
      puts({"name" => "Alice"}.inspect)
      puts 1r.inspect
      puts 3.14r.inspect
      puts 2i.inspect
      puts((1+2i).inspect)
      puts __ENCODING__
      a = __FILE__
      b = __LINE__
      base = { a: 1, b: 2 }
      merged = { **base, c: 3 }
      puts merged.inspect
    RUBY
    assert_equal 'puts ?a;puts "hello";puts "";puts :hello.inspect;puts :"hello world".inspect;puts %i[+ - ==].inspect;puts nil;puts (!!1).inspect;puts (!1).inspect;puts 42;puts -5;puts 1000000;puts 0.0;puts 3.14;puts 255;puts 10;puts [1,2,3].inspect;puts [].inspect;puts({a:1,b:2}.inspect);puts({1=>"one"}.inspect);puts({}.inspect);h_ops={:== =>1,:+ =>2,:<= =>3};puts h_ops[:==];h_nested={a:{b:{c:42}}};puts h_nested[:a][:b][:c];puts (1..5).to_a.inspect;puts (1...5).to_a.inspect;puts /hello/.inspect;puts /test/i.inspect;puts /test/mx.inspect;puts %w[foo bar baz].inspect;puts %i[foo bar baz].inspect;puts "tab:\there";puts({"name"=>"Alice"}.inspect);puts 1r.inspect;puts 3.14r.inspect;puts 2i.inspect;puts (1+2i).inspect;puts __ENCODING__;a=__FILE__;b=__LINE__;base={a:1,b:2};merged={**base,c:3};puts merged.inspect', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 2: Operator Precedence and Unary
  # Covers: +, -, *, /, %, ** precedence, bitwise &, |, <<,
  #   comparison, parentheses preservation/removal, right-associativity (**),
  #   unary minus, negative literals
  # ===========================================

  def test_operator_precedence
    result = minify_at_level(<<~'RUBY', 1)
      puts 1 + 2 * 3
      puts (5 - 2) * 4
      puts (3 + 4) / 2
      puts 12 / (3 + 1)
      puts 10 - 3 + 2
      puts 10 - (3 + 2)
      puts (2 + 3) ** 2
      puts 2 ** 3 ** 2
      x_op = 2 * 3 + 4 * 5
      puts x_op
      puts (10 + 3) % 4
      puts (1 + 2) << 3
      x_cmp = (3 + 2) > (1 + 1)
      puts x_cmp
      puts 0xFF & (0x0F | 0xF0)
      puts ((1 + 2) * 3) ** 2
      puts 2 ** -1
      x_neg = 5
      puts -(x_neg + 3)
      puts -1
      puts -3.14
      pattern = "hello"
      puts pattern !~ /xyz/
    RUBY
    assert_equal 'puts 7;puts 12;puts 3;puts 3;puts 9;puts 5;puts 25;puts 512;x_op=26;puts x_op;puts 1;puts 24;x_cmp=5>2;puts x_cmp;puts 255;puts 81;puts 2**-1;x_neg=5;puts -(x_neg+3);puts -1;puts -3.14;pattern="hello";puts pattern !~/xyz/', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 3: Variable Mangling, Scope Isolation, Dynamic Code Detection
  # Covers: local variable shortening, parameter mangling, scope reuse,
  #   top-level vars NOT mangled, eval/send/binding disable mangling,
  #   safe methods still mangled,
  #   special global variables NOT renamed ($stdout, $LOAD_PATH, $_, $1, $&, $`, $', $+, etc.)
  # ===========================================

  def test_variable_mangling
    result = minify_code(<<~RUBY)
      def method_with_mangling
        long_variable_name = 42
        another_long_name = long_variable_name + 1
        another_long_name
      end

      def greet_user(user_name, greeting_message)
        "\#{greeting_message}, \#{user_name}!"
      end
      puts greet_user("World", "Hello")

      def method_one
        local_var = 1
        local_var
      end
      def method_two
        local_var = 2
        local_var
      end
      puts method_one
      puts method_two

      top_level_var = 100
      puts top_level_var

      def calculate_with_eval(formula, value)
        eval(formula.gsub("x", value.to_s))
      end

      def call_method(object, method_name, argument)
        object.send(method_name, argument)
      end

      def get_value_via_binding(var_name)
        some_value = 42
        binding.local_variable_get(var_name)
      end

      def safe_method(long_parameter)
        local_variable = long_parameter * 2
        another_variable = local_variable + 10
        another_variable
      end
    RUBY
    assert_equal "def method_with_mangling;a=42;a+1;end;def a(a,b) =\"\#{b}, \#{a}!\";puts a(\"World\",\"Hello\");def b =1;def c =2;puts b;puts c;top_level_var=100;puts top_level_var;def calculate_with_eval(formula,value) =eval formula.gsub(?x,value.to_s);def call_method(a,b,c) =a.send(b,c);def get_value_via_binding(var_name);some_value=42;binding.local_variable_get(var_name);end;def safe_method(a);b=a*2;b+10;end", result.code
    assert_equal '', result.aliases

    # Special global variables must NOT be renamed
    result2 = minify_code(<<~'RUBY')
      puts $stdout.class
      puts $stderr.class
      puts $stdin.class
      puts $LOAD_PATH.class
      puts $LOADED_FEATURES.class
      puts $VERBOSE.inspect
      puts $DEBUG.inspect
      puts $PROGRAM_NAME.class
      puts $FILENAME.class
      puts $0.class
      puts $*.class
      puts $".class
      puts $:.class
      puts $<.class
      puts $>.class
      puts $/.inspect
      puts $\.inspect
      puts $,.inspect
      puts $;.inspect
      puts $..inspect
      puts $_.inspect
      puts $!.inspect
      puts $@.inspect
      puts $?.class
      puts $$.class
      puts $-0.inspect
      puts $-F.inspect
      puts $-I.class
      puts $-W.inspect
      puts $-a.inspect
      puts $-d.inspect
      puts $-i.inspect
      puts $-l.inspect
      puts $-p.inspect
      puts $-v.inspect
      puts $-w.inspect
      "hello 123" =~ /(\w+)\s(\d+)/
      puts $&
      puts $`
      puts $'
      puts $+
      puts $~[0]
      puts $1
      puts $2
      puts $3.inspect
      puts $4.inspect
      puts $5.inspect
      puts $6.inspect
      puts $7.inspect
      puts $8.inspect
      puts $9.inspect
    RUBY
    assert_equal 'puts $stdout.class;puts $stderr.class;puts $stdin.class;puts $:.class;puts $".class;puts $VERBOSE.inspect;puts $DEBUG.inspect;puts $0.class;puts $FILENAME.class;puts $0.class;puts $*.class;puts $".class;puts $:.class;puts $<.class;puts $>.class;puts $/.inspect;puts $\.inspect;puts $,.inspect;puts $;.inspect;puts $..inspect;puts $_.inspect;puts $!.inspect;puts $@.inspect;puts $?.class;puts $$.class;puts $-0.inspect;puts $-F.inspect;puts $-I.class;puts $-W.inspect;puts $-a.inspect;puts $-d.inspect;puts $-i.inspect;puts $-l.inspect;puts $-p.inspect;puts $-v.inspect;puts $-w.inspect;"hello 123"=~/(\w+)\s(\d+)/;puts $&;puts $`;puts $\';puts $+;puts $~[0];puts $1;puts $2;puts $3.inspect;puts $4.inspect;puts $5.inspect;puts $6.inspect;puts $7.inspect;puts $8.inspect;puts $9.inspect', result2.code
    assert_equal '', result2.aliases
  end

  # ===========================================
  # Group 4: Conditionals
  # Covers: if/else→ternary, if/else multiline, if/elsif/else→chained ternary,
  #   modifier if/unless, unless simple→if !, unless complex stays,
  #   unless/else→swapped if/else, ternary in assignment,
  #   ternary with symbol results (: spacing)
  # ===========================================

  def test_conditionals_and_elsif
    result = minify_at_level(<<~'RUBY', 1)
      def ternary_simple(x)
        if x > 5
          "big"
        else
          "small"
        end
      end
      puts ternary_simple(10)

      def multiline_if(x)
        if x > 0
          puts "positive"
          return x
        else
          puts "non-positive"
          return -x
        end
      end
      puts multiline_if(5)
      puts multiline_if(-3)

      def chained_if(x)
        if x > 10
          puts "big"
        elsif x > 0
          puts "small"
        else
          puts "neg"
        end
      end
      chained_if(3)

      flag = true
      puts "yes" if flag
      puts "no" unless flag

      flag2 = true
      unless flag2
        puts "hidden"
      end

      cond_a = true
      cond_b = false
      unless cond_a && cond_b
        puts "shown"
      end

      cond_c = true
      unless cond_c
        puts "branch_a"
        puts "branch_b"
      else
        puts "branch_c"
        puts "branch_d"
      end

      result_if = flag ? "t" : "f"
      puts result_if

      x_ternary = 5
      puts(x_ternary > 0 ? :yes : :no)

      val_type = 42
      if val_type.is_a?(Integer)
        puts "int" if val_type > 0
      else
        puts "other" if val_type
      end

      def test_elsif_fn(x)
        if x > 10
          puts "big"
          puts "very big"
        elsif x > 0
          puts "small"
          puts "medium"
        else
          puts "neg"
        end
      end
      test_elsif_fn(3)

      def classify(x)
        if x > 100
          puts "huge"
          puts "very huge"
        elsif x > 50
          puts "big"
          puts "very big"
        elsif x > 0
          puts "small"
          puts "medium"
        else
          puts "neg"
        end
      end
      classify(3)
    RUBY
    assert_equal 'def ternary_simple(x) =x>5?"big":"small";puts ternary_simple(10);def multiline_if(x);if x>0;puts "positive";x;else;puts "non-positive";-x;end;end;puts multiline_if(5);puts multiline_if(-3);def chained_if(x) =x>10?puts("big"):x>0?puts("small"):puts("neg");chained_if 3;flag=!!1;puts "yes" if flag;puts "no" if !flag;flag2=!!1;puts "hidden" if !flag2;cond_a=!!1;cond_b=!1;puts "shown" unless cond_a&&cond_b;cond_c=!!1;if cond_c;puts "branch_c";puts "branch_d";else;puts "branch_a";puts "branch_b";end;result_if=flag ? ?t:?f;puts result_if;x_ternary=5;puts x_ternary>0?:yes: :no;val_type=42;if val_type.is_a?(Integer);puts "int" if val_type>0;elsif val_type;puts "other";end;def test_elsif_fn(x);if x>10;puts "big";puts "very big";elsif x>0;puts "small";puts "medium";else;puts "neg";end;end;test_elsif_fn 3;def classify(x);if x>100;puts "huge";puts "very huge";elsif x>50;puts "big";puts "very big";elsif x>0;puts "small";puts "medium";else;puts "neg";end;end;classify 3', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 5: Loops, Case, Begin/Rescue/Ensure
  # Covers: while, until, while/until single-stmt→postfix form, multi-stmt→block form,
  #   begin..end while/until (do-while), case/when/else, begin/rescue/ensure, begin/rescue/else,
  #   multiple rescue clauses, rescue modifier,
  #   case/when with regex, case/when with range, case/when with class,
  #   while true with break, rescue with multiple exception types, ensure-only begin,
  #   ForNode, RetryNode, RedoNode, ForNode with MultiTargetNode index,
  #   FlipFlopNode (inclusive .., exclusive ...)
  # ===========================================

  def test_loops_and_rescue
    result = minify_at_level(<<~'RUBY', 1)
      i = 0
      while i < 3
        i += 1
      end
      puts i

      j = 0
      until j == 3
        j += 1
      end
      puts j

      k = 0
      k += 1 while k < 3
      puts k

      m = 0
      m += 1 until m >= 3
      puts m

      def classify_case(x)
        case x
        when 1, 2, 3
          "low"
        when 4, 5, 6
          "mid"
        else
          "high"
        end
      end
      puts classify_case(2)
      puts classify_case(5)
      puts classify_case(9)

      begin
        x_rescue = Integer("123")
      rescue ArgumentError => e
        x_rescue = 0
      ensure
        puts "done"
      end
      puts x_rescue

      begin
        x_else = 42
      rescue
        puts "error"
      else
        puts "no error"
      end

      begin
        raise ArgumentError, "arg err"
      rescue TypeError => e1
        puts "type"
      rescue ArgumentError => e2
        puts "arg"
      rescue => e3
        puts "other"
      end

      def risky_method
        result_r = (Integer("abc") rescue 0)
        puts result_r
      end
      risky_method

      str_case = "hello"
      case str_case
      when /hell/
        puts "matched regex"
      else
        puts "no match"
      end

      num_case = 3
      case num_case
      when 1..5
        puts "in range"
      else
        puts "out of range"
      end

      obj_case = 42
      case obj_case
      when Integer
        puts "is integer"
      else
        puts "not integer"
      end

      wt_count = 0
      while true
        break if wt_count >= 3
        wt_count += 1
      end
      puts wt_count

      begin
        raise ArgumentError, "test"
      rescue ArgumentError, TypeError => e
        puts e.message
      end

      begin
        puts "try"
      ensure
        puts "always"
      end

      multi_while_sum = 0
      multi_while_i = 1
      while multi_while_i <= 5
        multi_while_sum += multi_while_i
        multi_while_i += 1
      end
      puts multi_while_sum

      multi_until_sum = 0
      multi_until_i = 1
      until multi_until_i > 5
        multi_until_sum += multi_until_i
        multi_until_i += 1
      end
      puts multi_until_sum

      do_while_n = 0
      begin
        do_while_n += 1
      end while do_while_n < 3
      puts do_while_n

      do_while_once = 10
      begin
        do_while_once += 1
      end while do_while_once < 3
      puts do_while_once

      do_until_n = 0
      begin
        do_until_n += 1
      end until do_until_n >= 3
      puts do_until_n

      do_until_once = 10
      begin
        do_until_once += 1
      end until do_until_once >= 3
      puts do_until_once

      for item in [10, 20, 30]
        puts item
      end

      attempt_count = 0
      begin
        attempt_count += 1
        raise "err" if attempt_count < 3
      rescue
        retry if attempt_count < 3
      end
      puts attempt_count

      count = 0
      loop do
        count += 1
        break if count > 2
        redo if count == 1
      end
      puts count

      for a, b in [[1, 2], [3, 4]]
        puts a + b
      end

      result_ff = []
      i_ff = 0
      while i_ff < 10
        i_ff += 1
        result_ff << i_ff if (i_ff == 3)..(i_ff == 5)
      end
      puts result_ff.inspect

      result_eff = []
      j_ff = 0
      while j_ff < 10
        j_ff += 1
        result_eff << j_ff if (j_ff == 3)...(j_ff == 5)
      end
      puts result_eff.inspect
    RUBY
    assert_equal 'i=0;i+=1 while i<3;puts i;j=0;j+=1 until j==3;puts j;k=0;k+=1 while k<3;puts k;m=0;m+=1 until m>=3;puts m;def classify_case(x);case x;when 1,2,3;"low";when 4,5,6;"mid";else;"high";end;end;puts classify_case(2);puts classify_case(5);puts classify_case(9);begin;x_rescue=Integer "123";rescue ArgumentError;x_rescue=0;ensure;puts "done";end;puts x_rescue;begin;x_else=42;rescue;puts "error";else;puts "no error";end;begin;raise ArgumentError,"arg err";rescue TypeError;puts "type";rescue ArgumentError;puts "arg";rescue;puts "other";end;def risky_method;result_r=(Integer("abc") rescue 0);puts result_r;end;risky_method;str_case="hello";case str_case;when /hell/;puts "matched regex";else;puts "no match";end;num_case=3;case num_case;when (1..5);puts "in range";else;puts "out of range";end;obj_case=42;case obj_case;when Integer;puts "is integer";else;puts "not integer";end;wt_count=0;while !!1;break if wt_count>=3;wt_count+=1;end;puts wt_count;begin;raise ArgumentError,"test";rescue ArgumentError,TypeError=>e;puts e.message;end;begin;puts "try";ensure;puts "always";end;multi_while_sum=0;multi_while_i=1;while multi_while_i<=5;multi_while_sum+=multi_while_i;multi_while_i+=1;end;puts multi_while_sum;multi_until_sum=0;multi_until_i=1;until multi_until_i>5;multi_until_sum+=multi_until_i;multi_until_i+=1;end;puts multi_until_sum;do_while_n=0;begin;do_while_n+=1;end while do_while_n<3;puts do_while_n;do_while_once=10;begin;do_while_once+=1;end while do_while_once<3;puts do_while_once;do_until_n=0;begin;do_until_n+=1;end until do_until_n>=3;puts do_until_n;do_until_once=10;begin;do_until_once+=1;end until do_until_once>=3;puts do_until_once;for item in [10,20,30];puts item;end;attempt_count=0;begin;attempt_count+=1;raise "err" if attempt_count<3;rescue;retry if attempt_count<3;end;puts attempt_count;count=0;loop{count+=1;break if count>2;redo if count==1};puts count;for a, b in [[1,2],[3,4]];puts a+b;end;result_ff=[];i_ff=0;while i_ff<10;i_ff+=1;result_ff<<i_ff if (i_ff == 3)..(i_ff == 5);end;puts result_ff.inspect;result_eff=[];j_ff=0;while j_ff<10;j_ff+=1;result_eff<<j_ff if (j_ff == 3)...(j_ff == 5);end;puts result_eff.inspect', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 6: Method Definitions and All Param Types
  # Covers: endless method (single expr), multi-statement def, empty def,
  #   rest (*args), keyword rest (**kw), post positionals, all param types combined,
  #   anonymous splat (*), anonymous double splat (**), block param (&blk),
  #   complex default values (expression-based)
  # ===========================================

  def test_method_defs
    result = minify_code(<<~'RUBY')
      def endless_single(name)
        puts name
      end
      endless_single("hello")

      def multi_stmt(x)
        y = x + 1
        puts y
      end
      multi_stmt(5)

      def noop_method
      end
      noop_method

      def f_rest(a, b, *rest)
        rest
      end
      puts f_rest(1, 2, 3, 4).inspect

      def f_kw(a, **kw)
        kw
      end
      puts f_kw(1, x: 2).inspect

      def f_post(a, *mid, last)
        [a, mid, last].inspect
      end
      puts f_post(1, 2, 3, 4)

      def f_all(a, b = 10, *rest, last, key:, opt_key: "x", **extra, &blk)
        [a, b, rest, last, key, opt_key, extra, blk.call].inspect
      end
      puts f_all(1, 2, 3, 4, 5, key: "k") { "block" }

      def f_anon(*)
        42
      end
      puts f_anon(1, 2)

      def f_anon_kw(**)
        42
      end
      puts f_anon_kw(a: 1)

      def f_block(&blk)
        blk.call(42)
      end
      puts f_block { |x| x * 2 }

      def f_complex_default(a, b = a * 2)
        a + b
      end
      puts f_complex_default(3)
      puts f_complex_default(3, 10)

      def setter_test=(val)
        @val = val
      end

      def f_forward(...)
        f_rest(...)
      end
      puts f_forward(1, 2, 3, 4).inspect
    RUBY
    assert_equal 'def b(a) =puts a;b "hello";def d(a);b=a+1;puts b;end;d 5;def c;end;c;def e(a,b,*c) =c;puts e(1,2,3,4).inspect;def l(a,**b) =b;puts l(1,x:2).inspect;def i(a,*b,c) =[a,b,c].inspect;puts i(1,2,3,4);def k(a,b=10,*c,d,key:,opt_key:?x,**e,&f) =[a,b,c,d,key,opt_key,e,f.call].inspect;puts k(1,2,3,4,5,key:?k){"block"};def j(*) =42;puts j(1,2);def f(**) =42;puts f(a:1);def h(&a) =a.call(42);puts h{_1*2};def a(a,b=a*2) =a+b;puts a(3);puts a(3,10);def setter_test=(a);@a=a;end;def g(...) =e(...);puts g(1,2,3,4).inspect', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 7: Method Renaming
  # Covers: basic rename with call sites, initialize preserved,
  #   question mark methods, polymorphic calls, collision with existing short method
  # ===========================================

  def test_method_renaming
    result = minify_code(<<~RUBY)
      class Calculator
        def compute_result(x, y)
          x + y
        end
        def run_calculation
          puts compute_result(1, 2)
          puts compute_result(3, 4)
          puts compute_result(5, 6)
        end
      end
      Calculator.new.run_calculation

      class Greeter
        def initialize(name)
          @name = name
        end
        def greet_person
          puts "Hello, \#{@name}"
        end
      end
      g = Greeter.new("Alice")
      g.greet_person
      g.greet_person
      g.greet_person

      class Checker
        def is_valid?(value)
          value > 0
        end
        def check_all
          puts is_valid?(1)
          puts is_valid?(2)
          puts is_valid?(-1)
        end
      end
      Checker.new.check_all

      class Dog
        def make_sound
          "Woof"
        end
      end
      class Cat
        def make_sound
          "Meow"
        end
      end
      animals = [Dog.new, Cat.new]
      animals.each { |a| puts a.make_sound }
      animals.each { |a| puts a.make_sound }

      class ServiceWithA
        def a
          "existing"
        end
        def compute_result(x)
          x * 2
        end
        def run_service
          puts a
          puts compute_result(1)
          puts compute_result(2)
          puts compute_result(3)
        end
      end
      ServiceWithA.new.run_service
    RUBY
    assert_equal "class Calculator;def a(a,b) =a+b;def b;puts a(1,2);puts a(3,4);puts a(5,6);end;end;Calculator.new.b;class Greeter;def initialize(a) =@a=a;def a =puts \"Hello, \#{@a}\";end;g=Greeter.new(\"Alice\");g.a;g.a;g.a;class Checker;def a(a) =a>0;def b;puts a(1);puts a(2);puts a(-1);end;end;Checker.new.b;class Dog;def a =\"Woof\";end;class Cat;def a =\"Meow\";end;animals=[Dog.new,Cat.new];animals.each{puts _1.a};animals.each{puts _1.a};class ServiceWithA;def a =\"existing\";def b(a) =a*2;def c;puts a;puts b(1);puts b(2);puts b(3);end;end;ServiceWithA.new.c", result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 8: alias/undef Safety, Dynamic Dispatch Safety
  # Covers: alias preserves method names, undef preserves method names,
  #   send(:sym)/method(:sym) prevent renaming,
  #   AliasGlobalVariableNode (alias $new $old)
  # ===========================================

  def test_alias_undef_dynamic
    result = minify_code(<<~'RUBY')
      class AliasService
        def original_method
          "original"
        end
        alias new_method original_method
        def run_service
          puts original_method
          puts new_method
          puts original_method
        end
      end
      AliasService.new.run_service

      class UndefService
        def removable_method
          "removed"
        end
        def keep_method
          "kept"
        end
        undef removable_method
        def run_service
          puts keep_method
          puts keep_method
          puts keep_method
        end
      end
      UndefService.new.run_service

      class SendSafe
        def compute_result
          42
        end
        def run_service
          puts compute_result
          puts compute_result
          puts send(:compute_result)
        end
      end
      SendSafe.new.run_service

      class MethodRefSafe
        def compute_result
          42
        end
        def run_service
          puts compute_result
          m = method(:compute_result)
          puts m.call
        end
      end
      MethodRefSafe.new.run_service

      alias $CUSTOM_OUT $stdout
    RUBY
    assert_equal 'class AliasService;def original_method ="original";alias new_method original_method;def a;puts original_method;puts new_method;puts original_method;end;end;AliasService.new.a;class UndefService;def removable_method ="removed";def a ="kept";undef removable_method;def b;puts a;puts a;puts a;end;end;UndefService.new.b;class SendSafe;def compute_result =42;def a;puts compute_result;puts compute_result;puts send(:compute_result);end;end;SendSafe.new.a;class MethodRefSafe;def compute_result =42;def a;puts compute_result;a=method :compute_result;puts a.call;end;end;MethodRefSafe.new.a;alias $CUSTOM_OUT $stdout', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 9: Dead Code Elimination
  # Covers: dead code after return, break, next, raise;
  #   conditional return preserves subsequent code; top-level return
  # ===========================================

  def test_dead_code
    result = minify_at_level(<<~'RUBY', 1)
      def dead_return(x)
        return x * 2
        puts "dead"
        x + 1
      end
      puts dead_return(5)

      result_break = []
      [1, 2, 3].each do |x|
        result_break << x
        break
        result_break << x * 10
      end
      puts result_break.inspect

      result_next = []
      [1, 2, 3].each do |x|
        result_next << x
        next
        result_next << x * 100
      end
      puts result_next.inspect

      def dead_raise
        raise "error"
        puts "unreachable"
      end
      begin
        dead_raise
      rescue => e
        puts e.message
      end

      def conditional_return(x)
        if x > 0
          return x
        end
        puts "reachable"
        -x
      end
      puts conditional_return(5)
      puts conditional_return(-3)

      puts "before"
      return
      puts "after"
    RUBY
    assert_equal 'def dead_return(x) =return x*2;puts dead_return(5);result_break=[];[1,2,3].each{|x|result_break<<x;break};puts result_break.inspect;result_next=[];[1,2,3].each{|x|result_next<<x;next};puts result_next.inspect;def dead_raise =raise "error";begin;dead_raise;rescue=>e;puts e.message;end;def conditional_return(x);return x if x>0;puts "reachable";-x;end;puts conditional_return(5);puts conditional_return(-3);puts "before";return', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 10: Blocks and Numbered Params
  # Covers: do..end→{}, numbered params auto-conversion (1 ref, 2 refs),
  #   no conversion 3+ refs, nested blocks, multi-param,
  #   multi-statement block, break/next with value in blocks,
  #   method chaining with blocks, inject/reduce with block,
  #   LambdaNode, ItLocalVariableReadNode (Ruby 3.4+ it)
  # ===========================================

  def test_blocks_and_params
    result = minify_code(<<~'RUBY')
      [1, 2, 3].each do |n|
        puts n
      end

      result_map = [1, 2, 3].map do |x|
        y = x * 2
        y + 1
      end
      puts result_map.inspect

      result_num = [1, 2, 3].map { _1 * 10 }
      puts result_num.inspect

      [1, 2, 3].select { |x| x > 0 && x < 5 }

      [1, 2, 3].map { |x| x + x + x }

      [[1, 2], [3, 4]].each do |arr|
        arr.map { |x| x * 2 }
      end

      {a: 1, b: 2}.each { |k, v| puts k.to_s + v.to_s }

      result_break2 = [1, 2, 3].each do |x|
        break x * 10 if x == 2
      end
      puts result_break2

      [1, 2, 3].each do |x|
        break if x == 2
        puts x
      end

      result_next2 = [1, 2, 3, 4, 5].map do |x|
        next 0 if x.even?
        x * 10
      end
      puts result_next2.inspect

      puts [1, 2, 3].select { |x| x.odd? }.map { |x| x * 10 }.inspect
      puts [1, 2, 3].inject(0) { |sum, x| sum + x }

      doubler = -> (x) { x * 2 }
      puts doubler.call(21)
      puts doubler.call(10)
      puts doubler.call(5)

      [1, 2, 3].each { puts it }

      reassigned = [1, 2].map { |x| x = x + 1; x }
      puts reassigned.inspect

      keys_only = {a: 1, b: 2}.map { |k, v| k.to_s }
      puts keys_only.inspect

      lambda_capture = [10, 20].map { |x| f = -> { x * 2 }; f.call }
      puts lambda_capture.inspect
    RUBY
    assert_equal '[1,2,3].each{puts _1};result_map=[1,2,3].map{y=_1*2;y+1};puts result_map.inspect;result_num=[1,2,3].map{_1*10};puts result_num.inspect;[1,2,3].select{_1>0&&_1<5};[1,2,3].map{|a|a+a+a};[[1,2],[3,4]].each{|a|a.map{_1*2}};{a:1,b:2}.each{puts _1.to_s+_2.to_s};result_break2=[1,2,3].each{break _1*10 if _1==2};puts result_break2;[1,2,3].each{break if _1==2;puts _1};result_next2=[1,2,3,4,5].map{next 0 if _1.even?;_1*10};puts result_next2.inspect;puts [1,2,3].select(&:odd?).map{_1*10}.inspect;puts [1,2,3].inject(0){_1+_2};doubler=->(x){x*2};puts doubler.call(21);puts doubler.call(10);puts doubler.call(5);[1,2,3].each{puts it};reassigned=[1,2].map{|a|a=a+1;a};puts reassigned.inspect;keys_only={a:1,b:2}.map{|a,b|a.to_s};puts keys_only.inspect;lambda_capture=[10,20].map{|a|f=->{a*2};f.call};puts lambda_capture.inspect', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 11: Classes, Modules, Constants, Attr
  # Covers: attr_reader→attr, attr_accessor single→attr :x,true, attr_accessor multi,
  #   nested modules, inheritance, include, self reference, alias in class,
  #   collision with inherited method, method_missing with splat,
  #   ClassVariableReadNode, ClassVariableWriteNode, OperatorNode (compound assignment)
  # ===========================================

  def test_classes_and_modules
    result = minify_code(<<~RUBY)
      class PersonAttr
        attr_reader :name
        attr_accessor :age
        def initialize(name, age)
          @name = name
          @age = age
        end
        alias to_s name
      end
      p_attr = PersonAttr.new("Alice", 30)
      puts p_attr.name
      p_attr.age = 31
      puts p_attr.age

      class FooAccessor
        attr_accessor :bar
      end

      class BarAccessor
        attr_accessor :bar, :baz
      end

      module OuterMod
        module InnerMod
          def self.hi
            "hello from inner"
          end
        end
      end
      puts OuterMod::InnerMod.hi

      module Greetable
        def hi
          "hello"
        end
      end
      class PersonInclude
        include Greetable
      end
      puts PersonInclude.new.hi

      class SelfRef
        def me
          self
        end
        def to_s
          "I am SelfRef"
        end
      end
      puts SelfRef.new.me

      class BaseForChild
        def a
          "base"
        end
      end
      class ChildOfBase < BaseForChild
        def compute_result
          a + a
        end
        def run_service
          puts compute_result
          puts compute_result
          puts compute_result
        end
      end
      ChildOfBase.new.run_service

      class MethodMissingDemo
        def method_missing(name, *args)
          puts "called \#{name}"
        end
      end
      mm = MethodMissingDemo.new
      mm.hello
      mm.world

      class Counter
        @@total = 0

        def self.increment
          @@total += 1
          @@total
        end
      end

      puts Counter.increment
      puts Counter.increment
      puts Counter.increment
    RUBY
    assert_equal "class PersonAttr;attr :name;attr :a,true;def initialize(a,b);@name=a;@a=b;end;alias to_s name;end;p_attr=PersonAttr.new(\"Alice\",30);puts p_attr.name;p_attr.a=31;puts p_attr.a;class FooAccessor;attr :bar,true;end;class BarAccessor;attr_accessor :bar,:baz;end;module OuterMod;module InnerMod;def self.hi =\"hello from inner\";end;end;puts OuterMod::InnerMod.hi;module Greetable;def hi =\"hello\";end;class PersonInclude;include Greetable;end;puts PersonInclude.new.hi;class SelfRef;def me =self;def to_s =\"I am SelfRef\";end;puts SelfRef.new.me;class BaseForChild;def a =\"base\";end;class ChildOfBase<BaseForChild;def b =a+a;def c;puts b;puts b;puts b;end;end;ChildOfBase.new.c;class MethodMissingDemo;def method_missing(a,*b) =puts \"called \#{a}\";end;mm=MethodMissingDemo.new;mm.hello;mm.world;class Counter;@@a=0;def self.a;@@a+=1;@@a;end;end;puts Counter.a;puts Counter.a;puts Counter.a", result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 12: Assignments and Index Operations
  # Covers: ||=, &&=, +=/-=/*=, index read/write, index compound (+=, ||=, &&=),
  #   attr writer (obj.val=), instance variable compound assignment, ivar ||=,
  #   range as array slice, negative array indexing,
  #   MultiWriteNode (destructuring), MultiWriteNode with rest+rights, splat-only multi-write,
  #   CallNode []= with multiple positional args
  # ===========================================

  def test_assignments
    result = minify_code(<<~'RUBY')
      x_or = nil
      x_or ||= 42
      puts x_or
      x_or ||= 99
      puts x_or

      x_and = 1
      x_and &&= 42
      puts x_and
      y_and = nil
      y_and &&= 42
      puts y_and.inspect

      x_compound = 10
      x_compound += 5
      x_compound -= 3
      x_compound *= 2
      puts x_compound

      arr_idx = [10, 20, 30]
      arr_idx[1] += 5
      puts arr_idx.inspect

      h_idx = {}
      h_idx[:key] ||= "default"
      puts h_idx[:key]
      h_idx[:key] ||= "other"
      puts h_idx[:key]

      h_and_idx = { a: 1 }
      h_and_idx[:a] &&= 99
      h_and_idx[:b] &&= 99
      puts h_and_idx.inspect

      class ObjWriter
        attr_accessor :val
      end
      o_writer = ObjWriter.new
      o_writer.val = 42
      puts o_writer.val

      class CounterIvar
        def initialize
          @count = 0
        end
        def increment
          @count += 1
          @count
        end
      end
      c_counter = CounterIvar.new
      puts c_counter.increment
      puts c_counter.increment

      class MemoIvar
        def value
          @value ||= "computed"
        end
      end
      m_memo = MemoIvar.new
      puts m_memo.value
      puts m_memo.value

      arr_slice = [10, 20, 30, 40, 50]
      puts arr_slice[1..3].inspect
      puts arr_slice[-1]

      def swap_values(first_val, second_val)
        first_val, second_val = second_val, first_val
        puts first_val
        puts second_val
      end

      swap_values(1, 2)
      swap_values(3, 4)
      swap_values(5, 6)

      def test_rest(arr)
        first, *middle, last = arr
        puts first
        puts middle.inspect
        puts last
      end
      test_rest([1, 2, 3, 4, 5])
      test_rest([10, 20, 30])
      test_rest([100, 200])

      *, last_val = [10, 20, 30]
      puts last_val

      arr = [1, 2, 3, 4, 5]
      arr[1, 2] = [20, 30]
      puts arr.inspect

      x_multi, y_multi, z_multi = [1, 2, []]
      puts x_multi
      puts y_multi
      puts z_multi.inspect

      arr2 = [10, 20, 30]
      arr2[0], arr2[1] = arr2[1], arr2[0]
      puts arr2.inspect

      class KeywordIdx
        def [](key:)
          key
        end
      end
      puts KeywordIdx.new[key: 42]

      c_splat, * = [1, 2, 3]
      puts c_splat
    RUBY
    assert_equal 'x_or=nil;x_or||=42;puts x_or;x_or||=99;puts x_or;x_and=1;x_and&&=42;puts x_and;y_and=nil;y_and&&=42;puts y_and.inspect;x_compound=10;x_compound+=5;x_compound-=3;x_compound*=2;puts x_compound;arr_idx=[10,20,30];arr_idx[1]+=5;puts arr_idx.inspect;h_idx={};h_idx[:key]||="default";puts h_idx[:key];h_idx[:key]||="other";puts h_idx[:key];h_and_idx={a:1};h_and_idx[:a]&&=99;h_and_idx[:b]&&=99;puts h_and_idx.inspect;class ObjWriter;attr :c,true;end;o_writer=ObjWriter.new;o_writer.c=42;puts o_writer.c;class CounterIvar;def initialize =@a=0;def c;@a+=1;@a;end;end;c_counter=CounterIvar.new;puts c_counter.c;puts c_counter.c;class MemoIvar;def c =@a||="computed";end;m_memo=MemoIvar.new;puts m_memo.c;puts m_memo.c;arr_slice=[10,20,30,40,50];puts arr_slice[(1..3)].inspect;puts arr_slice[-1];def a(a,b);a,b=b,a;puts a;puts b;end;a 1,2;a 3,4;a 5,6;def b(a);b,*c,d=a;puts b;puts c.inspect;puts d;end;b [1,2,3,4,5];b [10,20,30];b [100,200];*,last_val=10,20,30;puts last_val;arr=[1,2,3,4,5];arr[1,2]=[20,30];puts arr.inspect;x_multi,y_multi,z_multi=1,2,[];puts x_multi;puts y_multi;puts z_multi.inspect;arr2=[10,20,30];arr2[0],arr2[1]=arr2[1],arr2[0];puts arr2.inspect;class KeywordIdx;def [](key:) =key;end;puts KeywordIdx.new[key:42];c_splat,* =1,2,3;puts c_splat', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 13: String Interpolation, Safe Navigation, Method Chaining
  # Covers: string interpolation (variable, expression), interpolated symbol,
  #   safe navigation &.[], &.[]=, &.method chaining,
  #   method chain on logical expression,
  #   interpolation with method chain, ternary in interpolation
  # ===========================================

  def test_interpolation_and_navigation
    result = minify_at_level(<<~'RUBY', 1)
      name_interp = "world"
      x_interp = 1
      puts "hello #{name_interp}"
      puts "val: #{x_interp + 1}"
      puts "#{name_interp} is #{x_interp}"

      sym_interp = "foo"
      sym_val = :"pre_#{sym_interp}_post"
      puts sym_val

      hash_nav = {a: 1}
      puts hash_nav&.[](:a)
      puts nil&.[](:a).inspect

      hash_nav2 = {a: 1}
      hash_nav2&.[]=(:b, 2)
      puts hash_nav2.inspect

      h_safe = { a: { b: "hello" } }
      puts h_safe&.dig(:a, :b)&.upcase
      puts nil&.dig(:a)&.upcase.inspect

      a_logic = true
      b_logic = false
      puts (a_logic || b_logic).to_s
      puts (a_logic && b_logic).to_s

      arr_interp = [1, 2, 3]
      puts "sum: #{arr_interp.sum}"
      x_interp2 = 5
      puts "x is #{x_interp2 > 0 ? 'big' : 'small'}"

      chain_comment = "hello"
      # this comment should not break the chain
      .upcase
      puts chain_comment
    RUBY
    assert_equal "name_interp=\"world\";x_interp=1;puts \"hello \#{name_interp}\";puts \"val: \#{x_interp+1}\";puts \"\#{name_interp} is \#{x_interp}\";sym_interp=\"foo\";sym_val=:\"pre_\#{sym_interp}_post\";puts sym_val;hash_nav={a:1};puts hash_nav&.[](:a);puts nil&.[](:a).inspect;hash_nav2={a:1};hash_nav2&.[]=(:b,2);puts hash_nav2.inspect;h_safe={a:{b:\"hello\"}};puts h_safe&.dig(:a,:b)&.upcase;puts nil&.dig(:a)&.upcase.inspect;a_logic=!!1;b_logic=!1;puts (a_logic||b_logic).to_s;puts (a_logic&&b_logic).to_s;arr_interp=[1,2,3];puts \"sum: \#{arr_interp.sum}\";x_interp2=5;puts \"x is \#{x_interp2>0?\"big\":\"small\"}\";chain_comment=\"hello\".upcase;puts chain_comment", result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 14: Logical Operators and Negation
  # Covers: !(a && b), !(a || b), a && (b || c), (a || b) && (c || d),
  #   !a && b vs !(a && b), &&/|| precedence, compound logical expressions
  # ===========================================

  def test_logical_and_negation
    result = minify_at_level(<<~'RUBY', 1)
      def neg_and(a_val, b_val)
        !(a_val && b_val)
      end
      def neg_or(a_val, b_val)
        !(a_val || b_val)
      end
      puts neg_and(true, false)
      puts neg_or(false, false)

      def check_and_or(a_val, b_val, c_val)
        a_val && (b_val || c_val)
      end
      puts check_and_or(true, false, true)

      def check_complex(a_val, b_val, c_val, d_val)
        (a_val || b_val) && (c_val || d_val)
      end
      puts check_complex(false, true, false, true)

      def not_and(a_val, b_val)
        !a_val && b_val
      end
      def not_or(a_val, b_val)
        !a_val || b_val
      end
      puts not_and(false, true)
      puts not_or(true, false)

      la = true
      lb = false
      lc = true
      puts la && lb
      puts la || lb
      puts la || lb && lc
      puts((la || lb) && lc)
      puts(la || (lb && lc))
    RUBY
    assert_equal 'def neg_and(a_val,b_val) =!(a_val&&b_val);def neg_or(a_val,b_val) =!(a_val||b_val);puts neg_and(!!1,!1);puts neg_or(!1,!1);def check_and_or(a_val,b_val,c_val) =a_val&&(b_val||c_val);puts check_and_or(!!1,!1,!!1);def check_complex(a_val,b_val,c_val,d_val) =(a_val||b_val)&&(c_val||d_val);puts check_complex(!1,!!1,!1,!!1);def not_and(a_val,b_val) =!a_val&&b_val;def not_or(a_val,b_val) =!a_val||b_val;puts not_and(!1,!!1);puts not_or(!!1,!1);la=!!1;lb=!1;lc=!!1;puts la&&lb;puts la||lb;puts la||lb&&lc;puts (la||lb)&&lc;puts la||lb&&lc', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 15: Super, Yield, Splat, Misc
  # Covers: super forwarding, super with args, yield with args,
  #   splat in array, conditional return, factorial recursion,
  #   regex match operator, regex with flags,
  #   yield with no args,
  #   DefinedNode, MatchWriteNode, InterpolatedRegexpNode,
  #   RegexpReferenceReadNode ($1), MatchLastLineNode, InterpolatedMatchLastLineNode,
  #   PostExecutionNode (END {})
  # ===========================================

  def test_super_yield_misc
    result = minify_at_level(<<~'RUBY', 1)
      class BaseSuper
        def hi
          "hello"
        end
      end
      class ChildSuper < BaseSuper
        def hi
          super + " world"
        end
      end
      puts ChildSuper.new.hi

      class BaseArgs
        def go(x)
          x * 2
        end
      end
      class ChildArgs < BaseArgs
        def go(x)
          super(x + 1)
        end
      end
      puts ChildArgs.new.go(5)

      def double_yield
        yield 1, 2
        yield 3, 4
      end
      double_yield { |a, b| puts a + b }

      arr_splat = [1, 2]
      b_splat = [0, *arr_splat, 3]
      puts b_splat.inspect

      def ok_return(n)
        return "yes" if n > 0
        "no"
      end
      puts ok_return(5)
      puts ok_return(-1)

      def factorial(n)
        n <= 1 ? 1 : n * factorial(n - 1)
      end
      puts factorial(5)

      puts "HELLO" =~ /hello/i
      str_re = "hello world 123"
      puts str_re.match(/\d+/)[0]

      def yield_no_args
        yield
      end
      yield_no_args { puts "hi" }

      puts defined?(String)
      /(?<matched_name>\w+)/ =~ "hello"
      puts matched_name

      def match_pattern(text_input, search_term)
        if text_input =~ /#{search_term}/i
          "found"
        else
          "not found"
        end
      end

      puts match_pattern("Hello World", "hello")
      puts match_pattern("Hello World", "xyz")
      puts match_pattern("Hello World", "world")

      "hello 123" =~ /(\d+)/
      puts $1

      END { puts "goodbye" }

      def yield_or_raise(flag)
        if flag
          yield 42
        else
          raise "err"
        end
      end
      yield_or_raise(true) { |v| puts v }
      yield_or_raise(false) {} rescue nil
    RUBY
    assert_equal 'class BaseSuper;def hi ="hello";end;class ChildSuper<BaseSuper;def hi =super+" world";end;puts ChildSuper.new.hi;class BaseArgs;def go(x) =x*2;end;class ChildArgs<BaseArgs;def go(x) =super(x+1);end;puts ChildArgs.new.go(5);def double_yield;yield 1,2;yield 3,4;end;double_yield{|a,b|puts a+b};arr_splat=[1,2];b_splat=[0,*arr_splat,3];puts b_splat.inspect;def ok_return(n);return "yes" if n>0;"no";end;puts ok_return(5);puts ok_return(-1);def factorial(n) =n<=1?1:n*factorial(n-1);puts factorial(5);puts "HELLO"=~/hello/i;str_re="hello world 123";puts str_re.match(/\d+/)[0];def yield_no_args =yield;yield_no_args{puts "hi"};puts defined?(String);/(?<matched_name>\w+)/=~"hello";puts matched_name;def match_pattern(text_input,search_term) =text_input=~/#{search_term}/i?"found":"not found";puts match_pattern("Hello World","hello");puts match_pattern("Hello World","xyz");puts match_pattern("Hello World","world");"hello 123"=~/(\d+)/;puts $1;END{puts "goodbye"};def yield_or_raise(flag) =flag ? yield(42):raise("err");yield_or_raise(!!1){|v|puts v};(yield_or_raise(!1){} rescue nil)', result.code
    assert_equal '', result.aliases

    # MatchLastLineNode, InterpolatedMatchLastLineNode
    result2 = minify_at_level(<<~'RUBY', 1)
      $_ = "hello world"
      puts "matched" if /hello/

      $_ = "test 123"
      word = "test"
      puts "found" if /#{word}/
    RUBY
    assert_equal '$_="hello world";puts "matched" if /hello/;$_="test 123";word="test";puts "found" if /#{word}/', result2.code
    assert_equal '', result2.aliases
  end

  # ===========================================
  # Group 16: Singleton Class Grouping
  # Covers: consecutive def self. methods grouped into class<<self block
  #   when 4+ consecutive, below threshold stays as def self.,
  #   instance method interrupts run, module support, mixed runs
  # ===========================================

  def test_singleton_class_grouping
    result = minify_at_level(<<~'RUBY', 1)
      # 4 consecutive → grouped into class<<self
      class SgA
        def self.a; 1; end
        def self.b; 2; end
        def self.c; 3; end
        def self.d; 4; end
      end
      puts SgA.a
      puts SgA.b
      puts SgA.c
      puts SgA.d

      # 3 consecutive → below threshold, stays as def self.
      class SgB
        def self.a; 1; end
        def self.b; 2; end
        def self.c; 3; end
      end
      puts SgB.a
      puts SgB.b
      puts SgB.c

      # instance method interrupts run → total 4 singleton defs, still grouped
      class SgC
        def self.a; 1; end
        def self.b; 2; end
        def x; 3; end
        def self.c; 4; end
        def self.d; 5; end
      end
      puts SgC.a
      puts SgC.b
      puts SgC.new.x
      puts SgC.c
      puts SgC.d

      # module support
      module SgD
        def self.a; 1; end
        def self.b; 2; end
        def self.c; 3; end
        def self.d; 4; end
      end
      puts SgD.a
      puts SgD.b
      puts SgD.c
      puts SgD.d

      # mixed: all 6 singleton defs grouped, instance method stays in place
      class SgE
        def self.a; 1; end
        def self.b; 2; end
        def self.c; 3; end
        def self.d; 4; end
        def x; 5; end
        def self.e; 6; end
        def self.f; 7; end
      end
      puts SgE.a
      puts SgE.b
      puts SgE.c
      puts SgE.d
      puts SgE.new.x
      puts SgE.e
      puts SgE.f
    RUBY
    # 4 consecutive → class<<self
    assert_equal true, result.code.include?('class SgA;class<<self;def a =1;def b =2;def c =3;def d =4;end;end')
    # 3 consecutive → def self.
    assert_equal true, result.code.include?('class SgB;def self.a =1;def self.b =2;def self.c =3;end')
    # interrupted run → still grouped
    assert_equal true, result.code.include?('class SgC;class<<self;def a =1;def b =2;def c =4;def d =5;end;def x =3;end')
    # module support
    assert_equal true, result.code.include?('module SgD;class<<self;def a =1;def b =2;def c =3;def d =4;end;end')
    # mixed
    assert_equal true, result.code.include?('class SgE;class<<self;def a =1;def b =2;def c =3;def d =4;def e =6;def f =7;end;def x =5;end')
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 17: Pattern matching
  # Covers: CaseMatchNode, ArrayPatternNode, CapturePatternNode, HashPatternNode,
  #   AltPatternNode (Integer | String), IfPatternNode (guard),
  #   PinnedPatternNode (^expr), MatchRequiredNode (standalone =>),
  #   MatchPredicateNode (standalone in)
  # ===========================================

  def test_pattern_matching
    result = minify_code(<<~'RUBY')
      def classify(input_value)
        case input_value
        in [Integer => first_num, Integer => second_num]
          puts first_num + second_num
        in {name: String => person_name}
          puts person_name
        else
          puts "unknown"
        end
      end

      classify([10, 20])
      classify({name: "Alice"})
      classify("other")

      case 42
      in Integer | String
        puts "number"
      end

      case [1, 2]
      in [Integer => x, Integer] if x > 0
        puts x
      end

      expected = 42
      case [42, 43]
      in [^expected, Integer => other]
        puts other
      end

      [1, 2, 3] => [Integer => first, *]
      puts first

      result_mp = [1, 2, 3] in [Integer, Integer, Integer]
      puts result_mp
    RUBY
    assert_equal 'def a(a);case a;in [Integer=>b,Integer=>c];puts b+c;in {name: String=>d};puts d;else;puts "unknown";end;end;a [10,20];a({name:"Alice"});a "other";case 42;in Integer | String;puts "number";end;case [1,2];in [Integer=>x,Integer] if x>0;puts x;end;expected=42;case [42,43];in [^expected,Integer=>other];puts other;end;[1,2,3]=>[Integer=>first,*];puts first;result_mp=[1,2,3] in [Integer,Integer,Integer];puts result_mp', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Singleton method with non-self receiver
  # ===========================================

  def test_def_with_constant_receiver_l1
    result = minify_at_level(<<~'RUBY', 1)
      module Foo; end
      def Foo.bar
        42
      end
      puts Foo.bar
    RUBY
    assert_equal 'module Foo;end;def Foo.bar =42;puts Foo.bar', result.code
    assert_equal '', result.aliases
  end

  def test_def_with_constant_receiver_renamed
    result = minify_code(<<~'RUBY')
      module Foo; end
      def Foo.bar
        42
      end
      puts Foo.bar
    RUBY
    assert_equal 'module Foo;end;def Foo.a =42;puts Foo.a', result.code
    assert_equal '', result.aliases
  end

end
