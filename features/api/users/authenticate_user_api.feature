@api @api_users @users_authenticate
Feature: Authenticate a user via the REST API
  In order to authenticate users programatically 
  As a Devleoper
  I want to authenticate users via the REST API

  Scenario: Authenticate a user with a correct password
    Given I am an administrator
    And a 'user' named 'alan_smith' exists
    And a 'authentication' named 'valid_password'
    When I 'POST' the 'authentication' to the path '/users/alan_smith/authentication'
    Then the inflated responses key 'authenticated' should exist
    And the inflated responses key 'authenticated' should be literally 'true'

  Scenario: Authenticate a user with a wrong private key
    Given I am an administrator
    And a 'user' named 'alan_smith' exists
    And an 'authentication' named 'valid_password'
    When I 'POST' the 'authentication' to the path '/users/alan_smith/authentication' using a wrong private key
    Then I should get a '401 "Unauthorized"' exception

  Scenario: Authenticate a user with a wrong password
    Given I am an administrator
    And a 'user' named 'alan_smith' exists
    And a 'authentication' named 'invalid_password'
    When I 'POST' the 'authentication' to the path '/users/alan_smith/authentication'
    Then the inflated responses key 'authenticated' should exist
    And the inflated responses key 'authenticated' should be literally 'false'






