@api @api_users @users_list
Feature: List users via the REST API
  In order to know what users exists programatically
  As a Developer
  I want to list all the users

  Scenario: List users when none have been created
    Given I am an administrator
      And there are no users 
     When I 'GET' the path '/users' 
     Then the inflated response should be '0' items long 

  Scenario: List users when one has been created
    Given I am an administrator
      And a 'user' named 'alan_smith' exists
     When I 'GET' the path '/users'
     Then the inflated responses key 'alan_smith' should match '^http://.+/users/alan_smith$'

  Scenario: List users when two have been created
     Given I am an administrator
       And a 'user' named 'alan_smith' exists
       And a 'user' named 'susan_jones' exists
      When I 'GET' the path '/users'
      Then the inflated response should be '2' items long
       And the inflated responses key 'alan_smith' should match '^http://.+/users/alan_smith$'
       And the inflated responses key 'susan_jones' should match '^http://.+/users/susan_jones$'

   Scenario: List users when none have been created with a wrong private key
     Given I am an administrator
       And there are no users 
      When I 'GET' the path '/users' using a wrong private key
      Then I should get a '401 "Unauthorized"' exception

