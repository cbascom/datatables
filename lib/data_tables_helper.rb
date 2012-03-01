module DataTablesHelper
  def datatables_with_delete(source, url, opts = {})
    options = opts.dup

    id_column = options.delete(:id_column) || 1
    options[:jquery] ||= {}
    options[:jquery][:oTableTools] ||= {}
    options[:jquery][:oTableTools][:aButtons] ||= []
    options[:jquery][:oTableTools][:aButtons] << {
      :sExtends => 'delete',
      :sAjaxUrl => url,
      :mColumns => [id_column]
    }
    options[:jquery][:aoColumnDefs] ||= []
    options[:jquery][:aoColumnDefs].unshift({
                                              :aTargets => [id_column],
                                              :bVisible => false
                                            })

    datatables_with_select(source, options)
  end

  def datatables_with_select(source, opts = {})
    options = opts.dup
    options[:jquery] ||= {}
    options[:jquery][:oTableTools] ||= {}
    options[:jquery][:oTableTools][:aButtons] ||= []
    options[:jquery][:oTableTools][:aButtons].unshift 'select_none'
    options[:jquery][:oTableTools][:aButtons].unshift 'select_all'
    options[:jquery][:oTableTools][:sRowSelect] ||= 'multi'

    datatables(source, options)
  end

  def datatables(source, opts = {})

    options = opts[:jquery] ? opts[:jquery].dup : {}
    options[:bJQueryUI] = true unless options.has_key?(:bJQueryUI)
    options[:bProcessing] = true unless options.has_key?(:bProcessing)
    options[:bServerSide] = true unless options.has_key?(:bServerSide)
    options[:bAutoWidth] = false unless options.has_key?(:bAutoWidth)
    options[:bStateSave] = true unless options.has_key?(:bStateSave)
    options[:oColVis] ||= {}
    options[:oColVis][:aiExclude] ||= []
    unless options[:oColVis][:aiExclude].include?(0)
      options[:oColVis][:aiExclude].unshift(0)
    end
    options[:aoColumnDefs] ||= []
    options[:aoColumnDefs].unshift({
                                     :aTargets => [0],
                                     :bSearchable => false,
                                     :bSortable => false
                                   })

    sdom = 'lfrtip'
    sdom = "C<\"clear\">" + sdom if options[:oColVis]
    sdom = 'T' + sdom if options[:oTableTools]
    options[:sDom] ||= sdom

    datatable = controller.datatable_source(source)
    options[:sAjaxSource] = method("#{datatable[:action]}_url".to_sym).call
    columns = datatable[:attrs].collect { |a| "<th>#{a}</th>" }.join

    if options[:html]
      html_opts = options[:html].collect { |k,v| "#{k}=\"#{v}\"" }.join(' ')
    end
    pad_ao_columns(options, datatable[:attrs].size)

    table_header = "<tr>#{columns}</tr>"
    html = "
<script>
$(document).ready(function() {
  var oTable = $('##{datatable[:action]}').dataTable({
#{datatables_option_string(options)}
  });
  $('tfoot input').keyup( function () {
                /* Filter on the column (the index) of this element */
                oTable.fnFilter( this.value, $('tfoot input').index(this) );
        } );

});
</script>
<table id=\"#{datatable[:action]}\" #{html_opts}>
<thead>
#{table_header}
</thead>
<tbody>
</tbody>
</table>
"
    return raw(html)
  end
end

def datatables_option_string(options, indent = 4)
  arr = []
  options.each do |key, value|
    if value.is_a?(String)
      arr << "#{' ' * indent}#{key}: '#{value}'"
    elsif value.is_a?(Array)
      indent += 2
      item_arr = []
      value.each do |item|
        if item.is_a?(Hash)
          str = "#{' ' * indent}{\n"
          str += "#{datatables_option_string(item, indent + 2)}\n"
          str += "#{' ' * indent}}"
          item_arr << str
        elsif item.is_a?(String)
          item_arr << "#{' ' * indent}'#{item}'"
        else
          item_arr << "#{' ' * indent}#{item}"
        end
      end
      indent -= 2
      arr << "#{' ' * indent}#{key}: [\n#{item_arr.join(",\n")}\n#{' ' * indent}]"
    elsif value.is_a?(Hash)
      str = "#{' ' * indent}#{key}: {\n"
      str += "#{datatables_option_string(value, indent + 2)}\n"
      str += "#{' ' * indent}}"
      arr << str
    else
      arr << "#{' ' * indent}#{key}: #{value}"
    end
  end

  arr.join(",\n")
end

def pad_ao_columns(options, count)
  return unless options[:aoColumns]

  (count - options[:aoColumns].size).times do
    options[:aoColumns] << 'null'
  end
end
