@api @api_users @users_create
Feature: Create a user via the REST API
  In order to create users programatically 
  As a Devleoper
  I want to create users via the REST API
  
  Scenario: Create a new user 
    Given I am an administrator
      And a 'user' named 'alan_smith'
     When I 'POST' the 'user' to the path '/users' 
      And the inflated responses key 'uri' should match '^http://.+/users/alan_smith$'

  Scenario: Create a user that already exists
    Given I am an administrator
      And an 'user' named 'alan_smith'
     When I 'POST' the 'user' to the path '/users' 
      And I 'POST' the 'user' to the path '/users' 
     Then I should get a '409 "Conflict"' exception

  Scenario: Create a new user with a wrong private key
    Given I am an administrator
      And a 'user' named 'alan_smith'
     When I 'POST' the 'user' to the path '/users' using a wrong private key
     Then I should get a '401 "Unauthorized"' exception

  Scenario: Create a new user as a non-admin
    Given I am a non-admin
      And a 'user' named 'alan_smith'
     When I 'POST' the 'user' to the path '/users'
     Then I should get a '403 "Forbidden"' exception

