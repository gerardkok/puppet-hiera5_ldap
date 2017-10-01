require 'spec_helper'
describe 'hiera5_ldap' do
  context 'with default values for all parameters' do
    it { should contain_class('hiera5_ldap') }
  end
end
