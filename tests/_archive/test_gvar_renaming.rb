# frozen_string_literal: true

require_relative 'test_helper'

class TestGvarRenaming < Minitest::Test
  include MinifyTestHelper

  # ===========================================
  # Group 1: All gvar patterns
  # Covers: basic shortening, short gvars skipped,
  #   compound assignment (+=, ||=), multiple gvars sorted by savings,
  #   multi-write target
  # ===========================================

  def setup_group1
    @group1 ||= minify_code(<<~RUBY)
      $global_name = "hello"
      puts $global_name

      $x = 1
      puts $x

      $accumulator = 0
      $accumulator += 10
      puts $accumulator

      $first_global = 1
      $second_global = 2
      puts $first_global + $second_global

      $or_cache = nil
      $or_cache ||= "cached"
      puts $or_cache

      $first_val, $second_val = 10, 20
      puts $first_val
      puts $second_val
    RUBY
  end

  def test_gvar_renaming
    result = setup_group1
    assert_equal '$e="hello";puts $e;$x=1;puts $x;$a=0;$a+=10;puts $a;$d=1;$c=2;puts $d+$c;$b=nil;$b||="cached";puts $b;$g,$f=10,20;puts $g;puts $f', result.code
    assert_equal '', result.aliases
  end
end
