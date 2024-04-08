# frozen_string_literal: true

# Taking out of puppet's Vault book
require 'puppet'
begin
  require 'aws-sdk-secretsmanager'
rescue LoadError
  raise Puppet::DataBinding::LookupError, '[AWSSM]: Must install aws-sdk-secretsmanager gem on both agent and server ruby versions to use awssm_lookup'
end
module PuppetX
  module GRiggi
    module AWSSM
      # First module for AWSSM, to lookup a given key (and optionally version)
      class Lookup
        def self.lookup(cache:, id:, region: 'us-east-2', version: nil, cache_stale: 30, ignore_cache: false)
          cache_key = [id, version, region]
          cache_hash = cache.retrieve(self)
          cached_result = cache_hash[cache_key] unless ignore_cache
          cache_use = false
          if cached_result
            # ! Not currently working as expected
            if (cached_result['date'] <=> Time.now - (cache_stale * 60)) == 1
              Puppet.debug '[AWSSM]: Returning cached value that is still fresh'
              cache_use = true
              return cached_result['data']
            end
            Puppet.debug '[AWSSM]: Cached value is stale, fetching new one'
          end
          result = get_secret(id: id,
                              version: version,
                              region: region)
          to_cache = {
            data: result,
            date: Time.now
          }
          if cache_use
            cache_hash[cache_key] = to_cache
            Puppet.debug '[AWSSM]: New value stored in cache'
          end
          result
        end

        def self.get_secret(id:, version:, region:)
          secret = nil
          response = nil
          awssm = Aws::SecretsManager::Client.new({
                                                    region: region
                                                  })
          begin
            response = awssm.get_secret_value({
                                                secret_id: id,
                                                version_id: version
                                              })
          rescue Aws::SecretsManager::Errors::ResourceNotFoundException
            raise Puppet::Error, "[AWSSM]: No matching key #{id} + version #{version} found."
          rescue Aws::SecretsManager::Errors::ServiceError => e
            raise Puppet::Error, "[AWSSM]: Non-specific error when looking up #{id}: #{e.message}"
          end
          unless response.nil?
            response = response.to_h
            Puppet.debug '[AWSSM]: Response received.'
            secret = if response[:secret_string]
                       response[:secret_string]
                     else
                       response[:secret_binary]
                     end
          end
          Puppet::Pops::Types::PSensitiveType::Sensitive.new(secret)
        end
      end
    end
  end
end
