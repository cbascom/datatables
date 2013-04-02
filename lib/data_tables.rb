require "data_tables/data_tables_helper"
module DataTablesController
  def self.included(cls)
    cls.extend(ClassMethods)
  end

  module ClassMethods
    def datatables_source(action, model,  *attrs)
      modelCls = Kernel.const_get(model.to_s.split("_").collect(&:capitalize).join)
      modelAttrs = nil
      if modelCls < Ohm::Model
        if Gem.loaded_specs['ohm'].version == Gem::Version.create('0.1.5')
          modelAttrs = Hash[*modelCls.new.attributes.collect { |v| [v.to_s, nil] }.flatten]
        else
          modelAttrs = {}
        end
      else
        modelAttrs = modelCls.new.attributes
      end
      columns = []
      modelAttrs.each_key { |k| columns << k }

      options = {}
      attrs.each do |option|
        option.each { |k,v| options[k] = v }
      end

      # override columns
      columns = options_to_columns(options) if options[:columns]

      # define columns so they are accessible from the helper
      define_columns(modelCls, columns, action)

      # define method that returns the data for the table
      define_datatables_action(self, action, modelCls, columns, options)
    end

    # named_scope is a combination table that include everything shown in UI.
    # except is the codition used for Ohm's except method, it should be key-value format,
    # such as [['name', 'bluesocket'],['id','1']].
    def define_datatables_action(controller, action, modelCls, columns, options = {})
      conditions = options[:conditions] || []
      scope = options[:scope] || :domain
      named_scope = options[:named_scope]
      named_scope_args = options[:named_scope_args]
      except = options[:except]
      es_block = options[:es_block]

      #
      # ------- Ohm ----------- #
      #
      if modelCls < Ohm::Model
        define_method action.to_sym do
          logger.debug "[tire] (datatable:#{__LINE__}) #{action.to_sym} #{modelCls} < Ohm::Model"
          if scope == :domain
            domain = ActiveRecord::Base.connection.schema_search_path.to_s.split(",")[0]
            return if domain.nil?
          end
          search_condition = params[:sSearch].blank? ? nil : params[:sSearch].to_s
          records = scope == :domain ? modelCls.find(:domain => domain) : modelCls.all
          if except
            except.each do |f|
              records = records.except(f[0].to_sym => f[1])
            end
          end
          total_records = records.size

          sort_column = params[:iSortCol_0].to_i
          sort_column = 1 if sort_column == 0
          current_page = (params[:iDisplayStart].to_i/params[:iDisplayLength].to_i rescue 0) + 1
          per_page = params[:iDisplayLength].to_i || 10
          sort_dir = params[:sSortDir_0] || 'desc'
          column_name_sym = columns[sort_column][:name].to_sym

          objects = nil

          if defined? Tire
            #
            # ----------- Elasticsearch/Tire for Ohm ----------- #
            #
            elastic_index_name = modelCls.to_s.underscore
            logger.debug "*** (datatable:#{__LINE__}) Using tire for search #{modelCls} (#{elastic_index_name})"

            search_condition = elasticsearch_sanitation(search_condition, except)
            just_excepts = except ? elasticsearch_sanitation(nil, except) : "*"
            logger.debug "*** search_condition = #{search_condition}; sort by #{column_name_sym}:#{sort_dir}; domain=`#{domain.inspect}'"

            retried = 0
            begin
              results = Tire.search(elastic_index_name) do
                if retried < 2
                  query { string search_condition }
                else
                  query { string just_excepts }
                end
                sort{ by column_name_sym, sort_dir } if retried < 1
                filter(:term, domain: domain) unless domain.blank?
                es_block.call(self) if es_block.respond_to?(:call)
                from (current_page-1) * per_page
                size per_page
              end.results

              objects = results.map{ |r| modelCls[r.id] }.compact
              total_display_records = results.total
            rescue Tire::Search::SearchRequestFailed => e
              logger.info "*** ERROR: Tire::Search::SearchRequestFailed => #{e.inspect} "
              if retried < 2
                retried += 1
                logger.info "Will retry #(#{retried})."
                retry
              else
                objects = []
                total_display_records = 0
                total_records = 0
              end
            end
          else
            #
            # -------- Redis/Lunar search --------------- #
            #
            logger.debug "*** (datatable:#{__LINE__}) NOT using tire for search"
            options = {}
            domain_id = domain.split("_")[1].to_i if scope == :domain
            options[:domain] = domain_id .. domain_id if scope == :domain
            options[:fuzzy] = {columns[sort_column][:name].to_sym => search_condition}
            objects = Lunar.search(modelCls, options)
            total_display_records = objects.size
            if Gem.loaded_specs['ohm'].version == Gem::Version.create('0.1.5')
              objects = objects.sort(:by => columns[sort_column][:name].to_sym,
                                     :order => "ALPHA " + params[:sSortDir_0].capitalize,
                                     :start => params[:iDisplayStart].to_i,
                                     :limit => params[:iDisplayLength].to_i)
            else
              objects = objects.sort(:by => columns[sort_column][:name].to_sym,
                                     :order => "ALPHA " + params[:sSortDir_0].capitalize,
                                     :limit => [params[:iDisplayStart].to_i, params[:iDisplayLength].to_i])
            end
            # -------- Redis/Lunar search --------------- #
          end

          data = objects.collect do |instance|
            columns.collect { |column| datatables_instance_get_value(instance, column) }
          end
          render :text => {:iTotalRecords => total_records,
            :iTotalDisplayRecords => total_display_records,
            :aaData => data,
            :sEcho => params[:sEcho].to_i}.to_json
        end
      # ------- /Ohm ----------- #
      else # Non-ohm models
        # add_search_option will determine whether the search text is empty or not
        init_conditions = conditions.clone
        add_search_option = false

        if modelCls.ancestors.any?{|ancestor| ancestor.name == "Tire::Model::Search"}
          #
          # ------- Elasticsearch ----------- #
          #
          define_method action.to_sym do
            domain_name = ActiveRecord::Base.connection.schema_search_path.to_s.split(",")[0]
            logger.debug "*** Using ElasticSearch for #{modelCls.name}"
            objects =  []

            condstr = ""
            unless params[:sSearch].blank?
              sort_column_id = params[:iSortCol_0].to_i
              sort_column_id = 1 if sort_column_id == 0
              sort_column = columns[sort_column_id]
              if sort_column && sort_column.has_key?(:attribute)
                condstr = params[:sSearch].gsub(/_/, '\\\\_').gsub(/%/, '\\\\%')
              end
            end

            sort_column = params[:iSortCol_0].to_i
            sort_column = 1 if sort_column == 0
            current_page = (params[:iDisplayStart].to_i/params[:iDisplayLength].to_i rescue 0)+1
            per_page = params[:iDisplayLength] || 10
            column_name = columns[sort_column][:name] || 'message'
            sort_dir = params[:sSortDir_0] || 'desc'

            condstr = elasticsearch_sanitation(condstr)

            begin
              query = Proc.new do
                query { string(condstr) }
                filter(:term, domain: domain_name) unless domain_name.blank?
                es_block.call(self) if es_block.respond_to?(:call)
              end

              results = modelCls.search(page: current_page,
                                        per_page: per_page,
                                        sort: "#{column_name}:#{sort_dir}",
                                        &query)
              objects = results.to_a
              total_display_records = results.total
              total_records = modelCls.search(search_type: 'count') do
                filter(:term, domain: domain_name) unless domain_name.blank?
                es_block.call(self) if es_block.respond_to?(:call)
              end.total
            rescue Tire::Search::SearchRequestFailed => e
              logger.debug "[Tire::Search::SearchRequestFailed] #{e.inspect}\n#{e.backtrace.join("\n")}"
              objects = []
              total_display_records = 0
              total_records = 0
            end

            data = objects.collect do |instance|
              columns.collect { |column| datatables_instance_get_value(instance, column) }
            end

            render :text => {:iTotalRecords => total_records,
              :iTotalDisplayRecords => total_display_records,
              :aaData => data,
              :sEcho => params[:sEcho].to_i}.to_json
          end
          # ------- /Elasticsearch ----------- #
        else
          #
          # ------- Postgres ----------- #
          #
          logger.debug "(datatable) #{action.to_sym} #{modelCls} < ActiveRecord"

          define_method action.to_sym do
            condition_local = ''
            unless params[:sSearch].blank?
              sort_column_id = params[:iSortCol_0].to_i
              sort_column_id = 1 if sort_column_id == 0
              sort_column = columns[sort_column_id]
              condstr = params[:sSearch].gsub(/_/, '\\\\_').gsub(/%/, '\\\\%')

              search_columns = options[:columns].map{|e| e.class == Symbol ? e : nil }.compact
              condition_local = search_columns.map do |column_name|
                " ((text(#{column_name}) ILIKE '%#{condstr}%')) "
              end.compact.join(" OR ")
              condition_local = " ( #{condition_local} ) " unless condition_local.blank?
            end

            # We just need one conditions string for search at a time.  Every time we input
            # something else in the search bar we will pop the previous search condition
            # string and push the new string.
            if condition_local != ''
              if add_search_option == false
                conditions << condition_local
                add_search_option = true
              else
                if conditions != []
                  conditions.pop
                  conditions << condition_local
                end
              end
            else
              if add_search_option == true
                if conditions != []
                  conditions.pop
                  add_search_option = false
                end
              end
            end

            if named_scope
              args = named_scope_args ? Array(self.send(named_scope_args)) : []
              total_records = modelCls.send(named_scope, *args).count :conditions => init_conditions.join(" AND ")
              total_display_records = modelCls.send(named_scope, *args).count :conditions => conditions.join(" AND ")
            else
              total_records = modelCls.count :conditions => init_conditions.join(" AND ")
              total_display_records = modelCls.count :conditions => conditions.join(" AND ")
            end
            sort_column = params[:iSortCol_0].to_i
            sort_column = 1 if sort_column == 0
            current_page = (params[:iDisplayStart].to_i/params[:iDisplayLength].to_i rescue 0)+1
            if named_scope
                objects = modelCls.send(named_scope, *args).paginate(:page => current_page,
                                            :order => "#{columns[sort_column][:name]} #{params[:sSortDir_0]}",
                                            :conditions => conditions.join(" AND "),
                                            :per_page => params[:iDisplayLength])
            else
                objects = modelCls.paginate(:page => current_page,
                                            :order => "#{columns[sort_column][:name]} #{params[:sSortDir_0]}",
                                            :conditions => conditions.join(" AND "),
                                            :per_page => params[:iDisplayLength])
            end
            #logger.info("------conditions is #{conditions}")
            data = objects.collect do |instance|
              columns.collect { |column| datatables_instance_get_value(instance, column) }
            end
            render :text => {:iTotalRecords => total_records,
              :iTotalDisplayRecords => total_display_records,
              :aaData => data,
              :sEcho => params[:sEcho].to_i}.to_json
            #
            # ------- /Postgres ----------- #
            #
          end
        end
      end
    end

    private

    #
    # Takes a list of columns from options and transforms them
    #
    def options_to_columns(options)
      columns = []
      options[:columns].each do |column|
        if column.kind_of? Symbol # a column from the database, we don't need to do anything
          columns << {:name => column, :attribute => column}
        elsif column.kind_of? Hash
    col_hash = { :name => column[:name], :special => column }
          col_hash[:attribute] = column[:attribute] if column[:attribute]
          columns << col_hash
        end
      end
      columns
    end

    def define_columns(cls, columns, action)
      define_method "datatable_#{action}_columns".to_sym do
        columnNames = {}
        columns.each do |column|
          columnName = ''
          if column[:method] or column[:eval]
            columnName << I18n.t(column[:name], :default => column[:name].to_s)
          else
            columnName << I18n.t(column[:name].to_sym, :default => column[:name].to_s)
          end
          columnName << ' *' unless column.has_key?(:attribute)
          columnNames[columnName] = column.has_key?(:attribute) ? true : false
        end

        columnNames
      end
    end
  end

  def elasticsearch_sanitation(search_string, except)
    logger.debug "*** elasticsearch_sanitation.before = #{search_string} "
    search_string = '*' if search_string.blank?
    search_string = "(\"#{search_string}*\" OR #{search_string.gsub(":","\\:")}*) " unless search_string =~ /(\*|\")/
    exceptions = except.map { |f|  "NOT #{f[0]}:\"#{f[1]}\""}.join(" AND ") if except
    search_string += " AND " + exceptions if exceptions
    logger.debug "*** elasticsearch_sanitation.after = #{search_string} "
    search_string
  end

  # gets the value for a column and row
  def datatables_instance_get_value(instance, column)
    if column[:special]
      special = column[:special]

      if special[:method]
        return method(special[:method].to_sym).call(instance)
      elsif special[:eval]
        proc = lambda { obj = instance; binding }
        return Kernel.eval(special[:eval], proc.call)
      end
    elsif column[:attribute]
      val = instance.send(column[:attribute].to_sym)
      return I18n.t(val.to_s.to_sym, :default => val.to_s) if not val.blank?
      return ''
    end
    return "value not found"
  end

  def datatable_source(name)
    {:action => name, :attrs => method("datatable_#{name}_columns".to_sym).call}
  end
end
