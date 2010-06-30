@api @api_users @users_update
Feature: Update a user
  In order to keep my user data up-to-date
  As a Developer
  I want to update my user via the API 

  Scenario: Update a user with a wrong private key
    Given I am an administrator
      And a 'user' named 'alan_smith' exists
      And sending the method 'openid=' to the 'user' with 'http://example.com/gorilla'
     When I 'PUT' the 'user' to the path '/users/alan_smith' using a wrong private key
     Then I should get a '401 "Unauthorized"' exception

  Scenario: Update a user as a non-admin
    Given I am a non-admin
      And a 'user' named 'alan_smith' exists
      And sending the method 'openid=' to the 'user' with 'http://example.com/gorilla'
     When I 'PUT' the 'user' to the path '/users/alan_smith'
     Then I should get a '403 "Forbidden"' exception

  Scenario: Update a user
    Given I am an administrator
      And a 'user' named 'alan_smith' exists
      And sending the method 'openid=' to the 'user' with 'http://example.com/gorilla'
     When I 'PUT' the 'user' to the path '/users/alan_smith'
     Then the inflated response should respond to 'openid' with 'http://example.com/gorilla'
     When I 'GET' the path '/users/alan_smith'
     Then the inflated response should respond to 'openid' with 'http://example.com/gorilla'

  Scenario: Change a password
    Given I am an administrator
      And a 'user' named 'alan_smith' exists
      And an 'authentication' named 'changed_password'
      And sending the method 'new_password=' to the 'user' with 'changed_password'
      And sending the method 'confirm_new_password=' to the 'user' with 'changed_password'
     When I 'PUT' the 'user' to the path '/users/alan_smith'
     When I 'POST' the 'authentication' to the path '/users/alan_smith/authentication'
     Then the inflated responses key 'authenticated' should exist
      And the inflated responses key 'authenticated' should be literally 'true'

  Scenario: Attempt to change password with bad password confirmation
    Given I am an administrator
      And a 'user' named 'alan_smith' exists
      And an 'authentication' named 'changed_password'
      And sending the method 'new_password=' to the 'user' with 'changed_password'
      And sending the method 'confirm_new_password=' to the 'user' with 'bad_password'
     When I 'PUT' the 'user' to the path '/users/alan_smith'
     When I 'POST' the 'authentication' to the path '/users/alan_smith/authentication'
     Then the inflated responses key 'authenticated' should exist
      And the inflated responses key 'authenticated' should be literally 'false'

  Scenario: Change a password and check it doesn't show on a subsequent GET
    Given I am an administrator
      And a 'user' named 'alan_smith' exists
      And an 'authentication' named 'changed_password'
      And sending the method 'new_password=' to the 'user' with 'changed_password'
      And sending the method 'confirm_new_password=' to the 'user' with 'changed_password'
     When I 'PUT' the 'user' to the path '/users/alan_smith'
     When I 'GET' the path '/users/alan_smith'
     Then the inflated response should respond to 'new_password' and match 'null' as json
     Then the inflated response should respond to 'confirm_new_password' and match 'null' as json

