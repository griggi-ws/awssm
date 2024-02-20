# frozen_string_literal: true

# Taking out of puppet's Vault book
require 'puppet'
begin
  require 'aws-sdk-secretsmanager'
rescue LoadError
  raise Puppet::DataBinding::LookupError, '[awssm_lookup] Must install aws-sdk-secretsmanager gem on both agent and server ruby versions to use awssm_lookup'
end
# First module for AWSSM, to lookup a given key (and optionally version)
module PuppetX
  module GRiggi
    module AWSSM
      class Lookup
        def self.lookup(cache:, id:, version: nil, region: 'us-east-2', cache_stale: 30, ignore_cache: false)
          cache_key = [id, version, region]
          cache_hash = cache.retrieve(self)
          cached_result = cache_hash[cache_key] unless ignore_cache
          if cached_result
            if cached_result['date'] <=> Time.now < cache_stale * 60
              Puppet.debug 'Returning cached value that is still fresh'
              return cached_result['data']
            end
            Puppet.debug 'Cached value is stale, fetching new one'
          end
          result = get_secret(id: id,
                              version: version,
                              region: region)
          to_cache = {
            data: result,
            date: Time.now
          }
          cache_hash[cache_key] = to_cache
          Puppet.debug 'New value stored in cache'
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
            raise Puppet::Error, "No matching key #{id} + version #{version} found."
          rescue Aws::SecretsManager::Errors::ServiceError => e
            raise Puppet::Error, "Non-specific error when looking up #{id}: #{e.message}"
          end
          unless response.nil?
            response = response.to_h
            secret = if response['secret_binary'].nil?
                       response['secret_string']
                     else
                       response['secret_binary']
                     end
          end
          Puppet::Pops::Types::PSensitiveType::Sensitive.new(secret)
        end
      end
    end
  end
end
