Description
-----------

A tool that will check facebook at dynamic intervals for pokes and respond with rutheless efficiancy.

Running
-------

Before you run, you need to create a config.rb file. The contents of which will look like this:

    module PokemonConfig

      USERNAME = "myemail@address.com"
      PASSWORD = "mypassword"

    #min and max wait time in seconds
      MAX_WAIT = 30*60
      MIN_WAIT = 1

    end

Then running is as simple as:

    ruby pokemon.rb
