require 'spec_helper'

describe 'select' do
  it { is_expected.to run.with_params([{'attr' => []}], 'attr').and_return([]) }
end
