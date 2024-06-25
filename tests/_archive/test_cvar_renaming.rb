# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'test_fixtures'

class TestCvarRenaming < Minitest::Test
  include MinifyTestHelper
  include RenameTestFixtures

  # ===========================================
  # Group 1: All cvar patterns
  # Covers: basic shortening, short cvars skipped,
  #   compound assignment (+=, ||=), independent classes,
  #   inheritance sharing, dynamic access exclusion
  # ===========================================

  def setup_group1
    @group1 ||= minify_code(<<~RUBY)
      class Counter
        @@total_count = 0
        def self.increment
          @@total_count += 1
          @@total_count
        end
      end
      puts Counter.increment
      puts Counter.increment

      class ShortCvar
        @@x = 1
        def self.get
          @@x
        end
      end
      puts ShortCvar.get

      class Multi
        @@first_value = 10
        @@second_value = 20
        def self.sum
          @@first_value + @@second_value
        end
      end
      puts Multi.sum

      class OrAssign
        @@cache = nil
        def self.value
          @@cache ||= "computed"
        end
      end
      puts OrAssign.value
      puts OrAssign.value

      class ParentCv
        @@shared_value = 0
        def self.write(val)
          @@shared_value = val
        end
      end
      class ChildCv < ParentCv
        def self.read
          @@shared_value
        end
      end
      ParentCv.write(42)
      puts ChildCv.read

      class DynamicAccess
        @@secret = 123
        def self.get_secret
          class_variable_get(:@@secret)
        end
      end
      puts DynamicAccess.get_secret
    RUBY
  end

  def test_cvar_renaming
    result = setup_group1
    assert_equal 'class Counter;@@a=0;def self.a;@@a+=1;@@a;end;end;puts Counter.a;puts Counter.a;class ShortCvar;@@x=1;def self.a =@@x;end;puts ShortCvar.a;class Multi;@@b=10;@@a=20;def self.a =@@b+@@a;end;puts Multi.a;class OrAssign;@@a=nil;def self.a =@@a||="computed";end;puts OrAssign.a;puts OrAssign.a;class ParentCv;@@a=0;def self.a(a) =@@a=a;end;class ChildCv<ParentCv;def self.b =@@a;end;ParentCv.a(42);puts ChildCv.b;class DynamicAccess;@@secret=123;def self.a =class_variable_get :"@@secret";end;puts DynamicAccess.a', result.code
    assert_equal '', result.aliases
  end
end
