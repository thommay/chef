@api @api_users @users_show
Feature: Show a user via the REST API 
  In order to know what the details are for a User 
  As a Developer
  I want to show the details for a specific User
  
  Scenario: Show a user
    Given I am an administrator
      And a 'user' named 'alan_smith' exists
     When I 'GET' the path '/users/alan_smith'
     Then the inflated response should respond to 'name' with 'alan_smith'

  Scenario: Show a missing user
    Given I am an administrator
      And there are no users 
     When I 'GET' the path '/users/alan_smith'
     Then I should get a '404 "Not Found"' exception

  Scenario: Show a user with a wrong private key
    Given I am an administrator
      And a 'user' named 'alan_smith' exists
     When I 'GET' the path '/users/alan_smith' using a wrong private key
     Then I should get a '401 "Unauthorized"' exception

