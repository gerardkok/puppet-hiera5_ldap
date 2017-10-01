Puppet::Functions.create_function(:select) do
  dispatch :select do
    param 'Array[Hash]', :list
    param 'String', :attr
    return_type 'Array[String]'
  end

  def select(list, attr)
    list.map { |e| e[attr] }.flatten
  end
end
