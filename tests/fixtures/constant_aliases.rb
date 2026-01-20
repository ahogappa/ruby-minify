# Test fixture for constant aliasing
# Expected: UserAccount → A (3 uses), OrderProcessor → B (2 uses)

class UserAccount
  DEFAULT_ROLE = "user"
end

class OrderProcessor
  def process(user)
    UserAccount.new
    OrderProcessor.validate
    UserAccount::DEFAULT_ROLE
  end
end

UserAccount.new
