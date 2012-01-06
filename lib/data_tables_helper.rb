module DataTablesHelper
  def datatables(source, *attrs)
    datatable = controller.datatable_source(source)
    html_opts = []
    if attrs.last
      attrs.last.each { |k,v| html_opts << "#{k}=\"#{v}\"" }
    end
    html_opts = html_opts.join(' ')
    
    columns = datatable[:attrs].collect { |a| "<th>#{a}</th>" }.join
    column_nulls = datatable[:attrs].slice(1..-1).collect { |a| "null" }.join ","
    #footer_columns = datatable[:attrs].collect { |a| "<th><input type='text' name='search_#{a}' value='Search #{a}' class='search_init' /></th>" }.join
    #table_footer = "<tr>#{footer_columns}</tr>"
    
    table_header = "<tr>#{columns}</tr>"
    url = method("#{datatable[:action]}_url".to_sym).call
    html = "
<script>
$(document).ready(function() {
  var oTable = $('##{datatable[:action]}').dataTable({
    sDom: 'C<\"clear\">lfrtip',
    bJQueryUI: true,
    bProcessing: true,
		bServerSide: true,
		bAutoWidth: false,
		sAjaxSource: \"#{url}\",
		oColVis: {
			aiExclude: [ 0 ]
		},
		aoColumns: [
				{
				  bSearchable: false,
	        bSortable: false
				},
        #{column_nulls}
			],
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