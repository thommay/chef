@api @api_users @users_delete
Feature: Delete a User via the REST API 
  In order to remove a user 
  As a Developer 
  I want to delete a user via the REST API
  
  Scenario: Delete a User 
    Given I am an administrator
      And a 'user' named 'alan_smith' exists
     When I 'DELETE' the path '/users/alan_smith'
     Then the inflated response should respond to 'name' with 'alan_smith' 

  Scenario: Delete a User that does not exist
    Given I am an administrator
      And there are no users 
     When I 'DELETE' the path '/user/alan_smith'
     Then I should get a '404 "Not Found"' exception
    
  Scenario: Delete a User with a wrong private key
    Given I am an administrator
      And a 'user' named 'alan_smith' exists
     When I 'DELETE' the path '/users/alan_smith' using a wrong private key
     Then I should get a '401 "Unauthorized"' exception

  Scenario: Delete a User as a non-admin
    Given I am a non-admin
      And a 'user' named 'alan_smith' exists
     When I 'DELETE' the path '/users/alan_smith'
     Then I should get a '403 "Forbidden"' exception

