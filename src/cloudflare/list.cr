# src/cloudflare/list.cr
module Cloudflare
  # A page of results from a list endpoint, together with the
  # pagination metadata (`ResultInfo`) returned by the API.
  struct List(T)
    include Enumerable(T)

    getter results     : Array(T)
    getter result_info : ResultInfo?

    def initialize(@results : Array(T), @result_info : ResultInfo? = nil)
    end

    def each(& : T ->) : Nil
      results.each do |result|
        yield result
      end
    end

    def [](index : Int) : T
      results[index]
    end

    def size : Int32
      results.size
    end

    def empty? : Bool
      results.empty?
    end

    # Current page number, when the endpoint is paginated.
    def page : Int32?
      result_info.try &.page
    end

    # Number of results per page.
    def per_page : Int32?
      result_info.try &.per_page
    end

    # Number of results in this page.
    def count : Int32?
      result_info.try &.count
    end

    # Total number of results available.
    def total_count : Int32?
      result_info.try &.total_count
    end

    # Total number of pages available.
    def total_pages : Int32?
      result_info.try &.total_pages
    end
  end
end
