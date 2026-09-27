export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      ai_analyses: {
        Row: {
          cache_read_tokens: number | null
          completed_at: string | null
          cost_usd: number | null
          created_at: string
          id: string
          input_hash: string | null
          input_tokens: number | null
          kind: string
          model: string | null
          model_tier: string | null
          organization_id: string
          output: Json | null
          output_markdown: string | null
          output_tokens: number | null
          project_id: string
          prompt_version: string | null
          requested_by: string | null
          status: Database["public"]["Enums"]["job_status"]
          subject_ref: Json
          used_batch_api: boolean
        }
        Insert: {
          cache_read_tokens?: number | null
          completed_at?: string | null
          cost_usd?: number | null
          created_at?: string
          id?: string
          input_hash?: string | null
          input_tokens?: number | null
          kind: string
          model?: string | null
          model_tier?: string | null
          organization_id: string
          output?: Json | null
          output_markdown?: string | null
          output_tokens?: number | null
          project_id: string
          prompt_version?: string | null
          requested_by?: string | null
          status?: Database["public"]["Enums"]["job_status"]
          subject_ref?: Json
          used_batch_api?: boolean
        }
        Update: {
          cache_read_tokens?: number | null
          completed_at?: string | null
          cost_usd?: number | null
          created_at?: string
          id?: string
          input_hash?: string | null
          input_tokens?: number | null
          kind?: string
          model?: string | null
          model_tier?: string | null
          organization_id?: string
          output?: Json | null
          output_markdown?: string | null
          output_tokens?: number | null
          project_id?: string
          prompt_version?: string | null
          requested_by?: string | null
          status?: Database["public"]["Enums"]["job_status"]
          subject_ref?: Json
          used_batch_api?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "ai_analyses_project_id_organization_id_fkey"
            columns: ["project_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      api_keys: {
        Row: {
          created_at: string
          created_by: string | null
          expires_at: string | null
          id: string
          key_hash: string
          key_prefix: string
          last_used_at: string | null
          last_used_ip: unknown
          name: string
          organization_id: string
          project_id: string | null
          rate_limit_per_min: number
          revoked_at: string | null
          scopes: string[]
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          expires_at?: string | null
          id?: string
          key_hash: string
          key_prefix: string
          last_used_at?: string | null
          last_used_ip?: unknown
          name: string
          organization_id: string
          project_id?: string | null
          rate_limit_per_min?: number
          revoked_at?: string | null
          scopes?: string[]
        }
        Update: {
          created_at?: string
          created_by?: string | null
          expires_at?: string | null
          id?: string
          key_hash?: string
          key_prefix?: string
          last_used_at?: string | null
          last_used_ip?: unknown
          name?: string
          organization_id?: string
          project_id?: string | null
          rate_limit_per_min?: number
          revoked_at?: string | null
          scopes?: string[]
        }
        Relationships: [
          {
            foreignKeyName: "api_keys_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "api_keys_project_id_organization_id_fkey"
            columns: ["project_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      audit_issue_types: {
        Row: {
          category: string
          code: string
          description: string
          how_to_fix: string
          is_active: boolean
          severity: Database["public"]["Enums"]["issue_severity"]
          title: string
          weight: number
        }
        Insert: {
          category: string
          code: string
          description: string
          how_to_fix: string
          is_active?: boolean
          severity: Database["public"]["Enums"]["issue_severity"]
          title: string
          weight?: number
        }
        Update: {
          category?: string
          code?: string
          description?: string
          how_to_fix?: string
          is_active?: boolean
          severity?: Database["public"]["Enums"]["issue_severity"]
          title?: string
          weight?: number
        }
        Relationships: []
      }
      audit_issues: {
        Row: {
          audit_id: string
          created_at: string
          details: Json
          id: number
          issue_code: string
          organization_id: string
          page_id: number | null
          severity: Database["public"]["Enums"]["issue_severity"]
          url: string | null
        }
        Insert: {
          audit_id: string
          created_at?: string
          details?: Json
          id?: never
          issue_code: string
          organization_id: string
          page_id?: number | null
          severity: Database["public"]["Enums"]["issue_severity"]
          url?: string | null
        }
        Update: {
          audit_id?: string
          created_at?: string
          details?: Json
          id?: never
          issue_code?: string
          organization_id?: string
          page_id?: number | null
          severity?: Database["public"]["Enums"]["issue_severity"]
          url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_issues_audit_id_fkey"
            columns: ["audit_id"]
            isOneToOne: false
            referencedRelation: "site_audits"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_issues_issue_code_fkey"
            columns: ["issue_code"]
            isOneToOne: false
            referencedRelation: "audit_issue_types"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "audit_issues_page_id_fkey"
            columns: ["page_id"]
            isOneToOne: false
            referencedRelation: "audit_pages"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_log: {
        Row: {
          action: string
          actor_api_key_id: string | null
          actor_user_id: string | null
          created_at: string
          id: number
          metadata: Json
          organization_id: string | null
          target_id: string | null
          target_type: string | null
        }
        Insert: {
          action: string
          actor_api_key_id?: string | null
          actor_user_id?: string | null
          created_at?: string
          id?: never
          metadata?: Json
          organization_id?: string | null
          target_id?: string | null
          target_type?: string | null
        }
        Update: {
          action?: string
          actor_api_key_id?: string | null
          actor_user_id?: string | null
          created_at?: string
          id?: never
          metadata?: Json
          organization_id?: string | null
          target_id?: string | null
          target_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_log_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_pages: {
        Row: {
          audit_id: string
          canonical_url: string | null
          cls: number | null
          content_hash: string | null
          content_type: string | null
          crawled_at: string
          depth: number | null
          external_links: number | null
          h1: string | null
          id: number
          inp_ms: number | null
          internal_links: number | null
          is_indexable: boolean | null
          lcp_ms: number | null
          meta_description: string | null
          organization_id: string
          page_size_bytes: number | null
          response_ms: number | null
          status_code: number | null
          structured_data: string[] | null
          title: string | null
          url: string
          word_count: number | null
        }
        Insert: {
          audit_id: string
          canonical_url?: string | null
          cls?: number | null
          content_hash?: string | null
          content_type?: string | null
          crawled_at?: string
          depth?: number | null
          external_links?: number | null
          h1?: string | null
          id?: never
          inp_ms?: number | null
          internal_links?: number | null
          is_indexable?: boolean | null
          lcp_ms?: number | null
          meta_description?: string | null
          organization_id: string
          page_size_bytes?: number | null
          response_ms?: number | null
          status_code?: number | null
          structured_data?: string[] | null
          title?: string | null
          url: string
          word_count?: number | null
        }
        Update: {
          audit_id?: string
          canonical_url?: string | null
          cls?: number | null
          content_hash?: string | null
          content_type?: string | null
          crawled_at?: string
          depth?: number | null
          external_links?: number | null
          h1?: string | null
          id?: never
          inp_ms?: number | null
          internal_links?: number | null
          is_indexable?: boolean | null
          lcp_ms?: number | null
          meta_description?: string | null
          organization_id?: string
          page_size_bytes?: number | null
          response_ms?: number | null
          status_code?: number | null
          structured_data?: string[] | null
          title?: string | null
          url?: string
          word_count?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_pages_audit_id_fkey"
            columns: ["audit_id"]
            isOneToOne: false
            referencedRelation: "site_audits"
            referencedColumns: ["id"]
          },
        ]
      }
      competitor_domains: {
        Row: {
          common_keywords: number | null
          created_at: string
          created_by: string | null
          domain: string
          id: string
          label: string | null
          metrics_updated_at: string | null
          organic_keywords: number | null
          organic_traffic_est: number | null
          organization_id: string
          project_id: string
          referring_domains: number | null
          source: string
          updated_at: string
          visibility_score: number | null
        }
        Insert: {
          common_keywords?: number | null
          created_at?: string
          created_by?: string | null
          domain: string
          id?: string
          label?: string | null
          metrics_updated_at?: string | null
          organic_keywords?: number | null
          organic_traffic_est?: number | null
          organization_id: string
          project_id: string
          referring_domains?: number | null
          source?: string
          updated_at?: string
          visibility_score?: number | null
        }
        Update: {
          common_keywords?: number | null
          created_at?: string
          created_by?: string | null
          domain?: string
          id?: string
          label?: string | null
          metrics_updated_at?: string | null
          organic_keywords?: number | null
          organic_traffic_est?: number | null
          organization_id?: string
          project_id?: string
          referring_domains?: number | null
          source?: string
          updated_at?: string
          visibility_score?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "competitor_domains_project_id_organization_id_fkey"
            columns: ["project_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      competitor_keywords: {
        Row: {
          competitor_domain_id: string
          cpc_usd: number | null
          estimated_traffic: number | null
          gap_type: string | null
          id: number
          keyword: string
          keyword_difficulty: number | null
          keyword_normalized: string | null
          language_code: string
          location_code: number
          organization_id: string
          our_position: number | null
          position: number | null
          project_id: string
          search_intent: Database["public"]["Enums"]["search_intent"] | null
          search_volume: number | null
          snapshot_date: string
          url: string | null
        }
        Insert: {
          competitor_domain_id: string
          cpc_usd?: number | null
          estimated_traffic?: number | null
          gap_type?: string | null
          id?: never
          keyword: string
          keyword_difficulty?: number | null
          keyword_normalized?: string | null
          language_code: string
          location_code: number
          organization_id: string
          our_position?: number | null
          position?: number | null
          project_id: string
          search_intent?: Database["public"]["Enums"]["search_intent"] | null
          search_volume?: number | null
          snapshot_date?: string
          url?: string | null
        }
        Update: {
          competitor_domain_id?: string
          cpc_usd?: number | null
          estimated_traffic?: number | null
          gap_type?: string | null
          id?: never
          keyword?: string
          keyword_difficulty?: number | null
          keyword_normalized?: string | null
          language_code?: string
          location_code?: number
          organization_id?: string
          our_position?: number | null
          position?: number | null
          project_id?: string
          search_intent?: Database["public"]["Enums"]["search_intent"] | null
          search_volume?: number | null
          snapshot_date?: string
          url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "competitor_keywords_competitor_domain_id_fkey"
            columns: ["competitor_domain_id"]
            isOneToOne: false
            referencedRelation: "competitor_domains"
            referencedColumns: ["id"]
          },
        ]
      }
      integrations: {
        Row: {
          config: Json
          created_at: string
          created_by: string | null
          display_name: string | null
          id: string
          last_error: string | null
          last_synced_at: string | null
          organization_id: string
          project_id: string | null
          provider: string
          status: string
          updated_at: string
          vault_secret_id: string | null
        }
        Insert: {
          config?: Json
          created_at?: string
          created_by?: string | null
          display_name?: string | null
          id?: string
          last_error?: string | null
          last_synced_at?: string | null
          organization_id: string
          project_id?: string | null
          provider: string
          status?: string
          updated_at?: string
          vault_secret_id?: string | null
        }
        Update: {
          config?: Json
          created_at?: string
          created_by?: string | null
          display_name?: string | null
          id?: string
          last_error?: string | null
          last_synced_at?: string | null
          organization_id?: string
          project_id?: string | null
          provider?: string
          status?: string
          updated_at?: string
          vault_secret_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "integrations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "integrations_project_id_organization_id_fkey"
            columns: ["project_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      jobs: {
        Row: {
          attempts: number
          created_at: string
          dedupe_key: string | null
          finished_at: string | null
          heartbeat_at: string | null
          id: number
          last_error: string | null
          locked_at: string | null
          locked_by: string | null
          max_attempts: number
          organization_id: string | null
          payload: Json
          priority: number
          progress: number | null
          project_id: string | null
          queue: string
          result: Json | null
          run_after: string
          status: Database["public"]["Enums"]["job_status"]
        }
        Insert: {
          attempts?: number
          created_at?: string
          dedupe_key?: string | null
          finished_at?: string | null
          heartbeat_at?: string | null
          id?: never
          last_error?: string | null
          locked_at?: string | null
          locked_by?: string | null
          max_attempts?: number
          organization_id?: string | null
          payload?: Json
          priority?: number
          progress?: number | null
          project_id?: string | null
          queue: string
          result?: Json | null
          run_after?: string
          status?: Database["public"]["Enums"]["job_status"]
        }
        Update: {
          attempts?: number
          created_at?: string
          dedupe_key?: string | null
          finished_at?: string | null
          heartbeat_at?: string | null
          id?: never
          last_error?: string | null
          locked_at?: string | null
          locked_by?: string | null
          max_attempts?: number
          organization_id?: string | null
          payload?: Json
          priority?: number
          progress?: number | null
          project_id?: string | null
          queue?: string
          result?: Json | null
          run_after?: string
          status?: Database["public"]["Enums"]["job_status"]
        }
        Relationships: [
          {
            foreignKeyName: "jobs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      keyword_positions: {
        Row: {
          check_date: string
          checked_at: string
          depth_checked: number
          estimated_traffic: number | null
          keyword_id: string
          organization_id: string
          owns_ai_overview: boolean | null
          position: number | null
          project_id: string
          provider: string
          raw_ref: string | null
          serp_features: string[]
          title: string | null
          url: string | null
        }
        Insert: {
          check_date: string
          checked_at?: string
          depth_checked?: number
          estimated_traffic?: number | null
          keyword_id: string
          organization_id: string
          owns_ai_overview?: boolean | null
          position?: number | null
          project_id: string
          provider: string
          raw_ref?: string | null
          serp_features?: string[]
          title?: string | null
          url?: string | null
        }
        Update: {
          check_date?: string
          checked_at?: string
          depth_checked?: number
          estimated_traffic?: number | null
          keyword_id?: string
          organization_id?: string
          owns_ai_overview?: boolean | null
          position?: number | null
          project_id?: string
          provider?: string
          raw_ref?: string | null
          serp_features?: string[]
          title?: string | null
          url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "keyword_positions_keyword_id_fkey"
            columns: ["keyword_id"]
            isOneToOne: false
            referencedRelation: "keyword_tracking"
            referencedColumns: ["id"]
          },
        ]
      }
      keyword_tracking: {
        Row: {
          best_position: number | null
          competition: number | null
          cpc_usd: number | null
          created_at: string
          created_by: string | null
          current_position: number | null
          current_url: string | null
          depth: number
          device: Database["public"]["Enums"]["search_device"]
          frequency: Database["public"]["Enums"]["check_frequency"]
          id: string
          is_active: boolean
          keyword: string
          keyword_difficulty: number | null
          keyword_normalized: string | null
          language_code: string
          last_check_date: string | null
          location_code: number
          metrics_updated_at: string | null
          monthly_searches: Json | null
          next_check_at: string
          organization_id: string
          previous_position: number | null
          project_id: string
          search_engine: Database["public"]["Enums"]["search_engine"]
          search_intent: Database["public"]["Enums"]["search_intent"] | null
          search_volume: number | null
          serp_features: string[] | null
          tags: string[]
          target_url: string | null
          updated_at: string
        }
        Insert: {
          best_position?: number | null
          competition?: number | null
          cpc_usd?: number | null
          created_at?: string
          created_by?: string | null
          current_position?: number | null
          current_url?: string | null
          depth?: number
          device?: Database["public"]["Enums"]["search_device"]
          frequency?: Database["public"]["Enums"]["check_frequency"]
          id?: string
          is_active?: boolean
          keyword: string
          keyword_difficulty?: number | null
          keyword_normalized?: string | null
          language_code: string
          last_check_date?: string | null
          location_code: number
          metrics_updated_at?: string | null
          monthly_searches?: Json | null
          next_check_at?: string
          organization_id: string
          previous_position?: number | null
          project_id: string
          search_engine?: Database["public"]["Enums"]["search_engine"]
          search_intent?: Database["public"]["Enums"]["search_intent"] | null
          search_volume?: number | null
          serp_features?: string[] | null
          tags?: string[]
          target_url?: string | null
          updated_at?: string
        }
        Update: {
          best_position?: number | null
          competition?: number | null
          cpc_usd?: number | null
          created_at?: string
          created_by?: string | null
          current_position?: number | null
          current_url?: string | null
          depth?: number
          device?: Database["public"]["Enums"]["search_device"]
          frequency?: Database["public"]["Enums"]["check_frequency"]
          id?: string
          is_active?: boolean
          keyword?: string
          keyword_difficulty?: number | null
          keyword_normalized?: string | null
          language_code?: string
          last_check_date?: string | null
          location_code?: number
          metrics_updated_at?: string | null
          monthly_searches?: Json | null
          next_check_at?: string
          organization_id?: string
          previous_position?: number | null
          project_id?: string
          search_engine?: Database["public"]["Enums"]["search_engine"]
          search_intent?: Database["public"]["Enums"]["search_intent"] | null
          search_volume?: number | null
          serp_features?: string[] | null
          tags?: string[]
          target_url?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "keyword_tracking_project_id_organization_id_fkey"
            columns: ["project_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      organization_invitations: {
        Row: {
          accepted_at: string | null
          accepted_by: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string | null
          organization_id: string
          role: Database["public"]["Enums"]["org_role"]
          token_hash: string
        }
        Insert: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email: string
          expires_at?: string
          id?: string
          invited_by?: string | null
          organization_id: string
          role?: Database["public"]["Enums"]["org_role"]
          token_hash: string
        }
        Update: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string | null
          organization_id?: string
          role?: Database["public"]["Enums"]["org_role"]
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_invitations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_members: {
        Row: {
          created_at: string
          invited_by: string | null
          organization_id: string
          role: Database["public"]["Enums"]["org_role"]
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          invited_by?: string | null
          organization_id: string
          role?: Database["public"]["Enums"]["org_role"]
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          invited_by?: string | null
          organization_id?: string
          role?: Database["public"]["Enums"]["org_role"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_members_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          billing_email: string | null
          brand_accent_color: string | null
          brand_logo_path: string | null
          brand_name: string | null
          brand_primary_color: string | null
          country_code: string | null
          created_at: string
          created_by: string | null
          custom_report_domain: string | null
          default_locale: string
          id: string
          is_personal: boolean
          name: string
          report_footer_text: string | null
          settings: Json
          slug: string
          stripe_customer_id: string | null
          updated_at: string
          vat_id: string | null
        }
        Insert: {
          billing_email?: string | null
          brand_accent_color?: string | null
          brand_logo_path?: string | null
          brand_name?: string | null
          brand_primary_color?: string | null
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          custom_report_domain?: string | null
          default_locale?: string
          id?: string
          is_personal?: boolean
          name: string
          report_footer_text?: string | null
          settings?: Json
          slug: string
          stripe_customer_id?: string | null
          updated_at?: string
          vat_id?: string | null
        }
        Update: {
          billing_email?: string | null
          brand_accent_color?: string | null
          brand_logo_path?: string | null
          brand_name?: string | null
          brand_primary_color?: string | null
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          custom_report_domain?: string | null
          default_locale?: string
          id?: string
          is_personal?: boolean
          name?: string
          report_footer_text?: string | null
          settings?: Json
          slug?: string
          stripe_customer_id?: string | null
          updated_at?: string
          vat_id?: string | null
        }
        Relationships: []
      }
      plans: {
        Row: {
          created_at: string
          currency: string
          description: string | null
          id: string
          is_public: boolean
          limits: Json
          name: string
          price_monthly_cents: number
          price_yearly_cents: number
          sort_order: number
          stripe_price_monthly_id: string | null
          stripe_price_yearly_id: string | null
          stripe_product_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          currency?: string
          description?: string | null
          id: string
          is_public?: boolean
          limits?: Json
          name: string
          price_monthly_cents?: number
          price_yearly_cents?: number
          sort_order?: number
          stripe_price_monthly_id?: string | null
          stripe_price_yearly_id?: string | null
          stripe_product_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          currency?: string
          description?: string | null
          id?: string
          is_public?: boolean
          limits?: Json
          name?: string
          price_monthly_cents?: number
          price_yearly_cents?: number
          sort_order?: number
          stripe_price_monthly_id?: string | null
          stripe_price_yearly_id?: string | null
          stripe_product_id?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      projects: {
        Row: {
          archived_at: string | null
          client_contact: string | null
          client_name: string | null
          created_at: string
          created_by: string | null
          default_device: Database["public"]["Enums"]["search_device"]
          domain: string
          id: string
          is_client_project: boolean
          language_code: string
          location_code: number
          name: string
          organization_id: string
          root_url: string
          search_engine: Database["public"]["Enums"]["search_engine"]
          settings: Json
          tags: string[]
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          client_contact?: string | null
          client_name?: string | null
          created_at?: string
          created_by?: string | null
          default_device?: Database["public"]["Enums"]["search_device"]
          domain: string
          id?: string
          is_client_project?: boolean
          language_code?: string
          location_code?: number
          name: string
          organization_id: string
          root_url: string
          search_engine?: Database["public"]["Enums"]["search_engine"]
          settings?: Json
          tags?: string[]
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          client_contact?: string | null
          client_name?: string | null
          created_at?: string
          created_by?: string | null
          default_device?: Database["public"]["Enums"]["search_device"]
          domain?: string
          id?: string
          is_client_project?: boolean
          language_code?: string
          location_code?: number
          name?: string
          organization_id?: string
          root_url?: string
          search_engine?: Database["public"]["Enums"]["search_engine"]
          settings?: Json
          tags?: string[]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "projects_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      reports: {
        Row: {
          branding: Json
          created_at: string
          created_by: string | null
          html_path: string | null
          id: string
          last_rendered_at: string | null
          locale: string
          organization_id: string
          pdf_path: string | null
          period_end: string | null
          period_start: string | null
          project_id: string
          recipients: string[]
          report_type: string
          schedule_cron: string | null
          sections: Json
          share_expires_at: string | null
          share_token_hash: string | null
          status: Database["public"]["Enums"]["report_status"]
          title: string
          updated_at: string
          white_label: boolean
        }
        Insert: {
          branding?: Json
          created_at?: string
          created_by?: string | null
          html_path?: string | null
          id?: string
          last_rendered_at?: string | null
          locale?: string
          organization_id: string
          pdf_path?: string | null
          period_end?: string | null
          period_start?: string | null
          project_id: string
          recipients?: string[]
          report_type: string
          schedule_cron?: string | null
          sections?: Json
          share_expires_at?: string | null
          share_token_hash?: string | null
          status?: Database["public"]["Enums"]["report_status"]
          title: string
          updated_at?: string
          white_label?: boolean
        }
        Update: {
          branding?: Json
          created_at?: string
          created_by?: string | null
          html_path?: string | null
          id?: string
          last_rendered_at?: string | null
          locale?: string
          organization_id?: string
          pdf_path?: string | null
          period_end?: string | null
          period_start?: string | null
          project_id?: string
          recipients?: string[]
          report_type?: string
          schedule_cron?: string | null
          sections?: Json
          share_expires_at?: string | null
          share_token_hash?: string | null
          status?: Database["public"]["Enums"]["report_status"]
          title?: string
          updated_at?: string
          white_label?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "reports_project_id_organization_id_fkey"
            columns: ["project_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      site_audits: {
        Row: {
          config: Json
          created_at: string
          error_message: string | null
          errors_count: number
          finished_at: string | null
          health_score: number | null
          id: string
          notices_count: number
          organization_id: string
          pages_crawled: number
          pages_indexable: number | null
          pages_limit: number
          project_id: string
          queued_at: string
          report_html_path: string | null
          report_pdf_path: string | null
          started_at: string | null
          status: Database["public"]["Enums"]["audit_status"]
          summary: Json
          trigger_source: string
          triggered_by: string | null
          updated_at: string
          warnings_count: number
        }
        Insert: {
          config?: Json
          created_at?: string
          error_message?: string | null
          errors_count?: number
          finished_at?: string | null
          health_score?: number | null
          id?: string
          notices_count?: number
          organization_id: string
          pages_crawled?: number
          pages_indexable?: number | null
          pages_limit?: number
          project_id: string
          queued_at?: string
          report_html_path?: string | null
          report_pdf_path?: string | null
          started_at?: string | null
          status?: Database["public"]["Enums"]["audit_status"]
          summary?: Json
          trigger_source?: string
          triggered_by?: string | null
          updated_at?: string
          warnings_count?: number
        }
        Update: {
          config?: Json
          created_at?: string
          error_message?: string | null
          errors_count?: number
          finished_at?: string | null
          health_score?: number | null
          id?: string
          notices_count?: number
          organization_id?: string
          pages_crawled?: number
          pages_indexable?: number | null
          pages_limit?: number
          project_id?: string
          queued_at?: string
          report_html_path?: string | null
          report_pdf_path?: string | null
          started_at?: string | null
          status?: Database["public"]["Enums"]["audit_status"]
          summary?: Json
          trigger_source?: string
          triggered_by?: string | null
          updated_at?: string
          warnings_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "site_audits_project_id_organization_id_fkey"
            columns: ["project_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      subscriptions: {
        Row: {
          billing_interval: string
          cancel_at_period_end: boolean
          canceled_at: string | null
          created_at: string
          current_period_end: string | null
          current_period_start: string | null
          id: string
          limit_overrides: Json
          metadata: Json
          organization_id: string
          plan_id: string
          seats: number
          status: Database["public"]["Enums"]["subscription_status"]
          stripe_customer_id: string | null
          stripe_subscription_id: string | null
          trial_end: string | null
          updated_at: string
        }
        Insert: {
          billing_interval?: string
          cancel_at_period_end?: boolean
          canceled_at?: string | null
          created_at?: string
          current_period_end?: string | null
          current_period_start?: string | null
          id?: string
          limit_overrides?: Json
          metadata?: Json
          organization_id: string
          plan_id: string
          seats?: number
          status: Database["public"]["Enums"]["subscription_status"]
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          trial_end?: string | null
          updated_at?: string
        }
        Update: {
          billing_interval?: string
          cancel_at_period_end?: boolean
          canceled_at?: string | null
          created_at?: string
          current_period_end?: string | null
          current_period_start?: string | null
          id?: string
          limit_overrides?: Json
          metadata?: Json
          organization_id?: string
          plan_id?: string
          seats?: number
          status?: Database["public"]["Enums"]["subscription_status"]
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          trial_end?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "subscriptions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscriptions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["id"]
          },
        ]
      }
      usage_records: {
        Row: {
          api_key_id: string | null
          id: number
          idempotency_key: string
          job_id: number | null
          metadata: Json
          metric: Database["public"]["Enums"]["usage_metric"]
          occurred_at: string
          organization_id: string
          project_id: string | null
          provider: string | null
          provider_cost_usd: number | null
          quantity: number
          source: string
          stripe_reported_at: string | null
        }
        Insert: {
          api_key_id?: string | null
          id?: never
          idempotency_key: string
          job_id?: number | null
          metadata?: Json
          metric: Database["public"]["Enums"]["usage_metric"]
          occurred_at?: string
          organization_id: string
          project_id?: string | null
          provider?: string | null
          provider_cost_usd?: number | null
          quantity: number
          source?: string
          stripe_reported_at?: string | null
        }
        Update: {
          api_key_id?: string | null
          id?: never
          idempotency_key?: string
          job_id?: number | null
          metadata?: Json
          metric?: Database["public"]["Enums"]["usage_metric"]
          occurred_at?: string
          organization_id?: string
          project_id?: string | null
          provider?: string | null
          provider_cost_usd?: number | null
          quantity?: number
          source?: string
          stripe_reported_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "usage_records_api_key_id_fkey"
            columns: ["api_key_id"]
            isOneToOne: false
            referencedRelation: "api_keys"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usage_records_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usage_records_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_invitation: { Args: { p_token: string }; Returns: string }
      claim_jobs: {
        Args: {
          p_limit?: number
          p_queues: string[]
          p_stale_after?: string
          p_worker_id: string
        }
        Returns: {
          attempts: number
          created_at: string
          dedupe_key: string | null
          finished_at: string | null
          heartbeat_at: string | null
          id: number
          last_error: string | null
          locked_at: string | null
          locked_by: string | null
          max_attempts: number
          organization_id: string | null
          payload: Json
          priority: number
          progress: number | null
          project_id: string | null
          queue: string
          result: Json | null
          run_after: string
          status: Database["public"]["Enums"]["job_status"]
        }[]
        SetofOptions: {
          from: "*"
          to: "jobs"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      complete_job: {
        Args: { p_job_id: number; p_result?: Json; p_worker_id: string }
        Returns: undefined
      }
      create_api_key: {
        Args: {
          p_expires_at?: string
          p_name: string
          p_org_id: string
          p_project_id?: string
          p_scopes?: string[]
        }
        Returns: {
          api_key: string
          id: string
          key_prefix: string
        }[]
      }
      create_organization: {
        Args: { p_name: string; p_slug?: string }
        Returns: string
      }
      ctr_for_position: { Args: { p_position: number }; Returns: number }
      enqueue_due_rank_checks: {
        Args: { p_batch_size?: number }
        Returns: number
      }
      fail_job: {
        Args: {
          p_error: string
          p_job_id: number
          p_retryable?: boolean
          p_worker_id: string
        }
        Returns: undefined
      }
      get_usage_summary: {
        Args: { p_org_id: string }
        Returns: {
          metric: Database["public"]["Enums"]["usage_metric"]
          period_start: string
          quota: number
          used: number
        }[]
      }
      heartbeat_job: {
        Args: { p_job_id: number; p_progress?: number; p_worker_id: string }
        Returns: boolean
      }
      invite_member: {
        Args: {
          p_email: string
          p_org_id: string
          p_role?: Database["public"]["Enums"]["org_role"]
        }
        Returns: string
      }
      normalize_domain: { Args: { p_input: string }; Returns: string }
      normalize_keyword: { Args: { p_input: string }; Returns: string }
      project_rank_summary: {
        Args: { p_days?: number; p_project_id: string }
        Returns: {
          avg_position: number
          check_date: string
          checked: number
          est_traffic: number
          ranked: number
          top10: number
          top3: number
          visibility: number
        }[]
      }
      record_usage: {
        Args: {
          p_api_key_id?: string
          p_enforce_quota?: boolean
          p_idempotency_key: string
          p_job_id?: number
          p_metadata?: Json
          p_metric: Database["public"]["Enums"]["usage_metric"]
          p_org_id: string
          p_project_id?: string
          p_provider?: string
          p_provider_cost_usd?: number
          p_quantity: number
          p_source?: string
        }
        Returns: {
          allowed: boolean
          is_overage: boolean
          quota: number
          used: number
        }[]
      }
      request_site_audit: {
        Args: { p_config?: Json; p_project_id: string }
        Returns: string
      }
      revoke_api_key: { Args: { p_key_id: string }; Returns: undefined }
      verify_api_key: {
        Args: { p_api_key: string }
        Returns: {
          api_key_id: string
          organization_id: string
          project_id: string
          rate_limit_per_min: number
          scopes: string[]
        }[]
      }
    }
    Enums: {
      audit_status:
        | "queued"
        | "crawling"
        | "analyzing"
        | "completed"
        | "failed"
        | "cancelled"
      check_frequency: "daily" | "weekly" | "monthly"
      issue_severity: "notice" | "warning" | "error"
      job_status:
        | "queued"
        | "running"
        | "succeeded"
        | "failed"
        | "cancelled"
        | "dead"
      org_role: "viewer" | "admin" | "owner"
      report_status: "draft" | "queued" | "rendering" | "ready" | "failed"
      search_device: "desktop" | "mobile"
      search_engine: "google" | "bing"
      search_intent:
        | "informational"
        | "navigational"
        | "commercial"
        | "transactional"
      subscription_status:
        | "trialing"
        | "active"
        | "past_due"
        | "canceled"
        | "incomplete"
        | "incomplete_expired"
        | "unpaid"
        | "paused"
      usage_metric:
        | "serp_query"
        | "keyword_lookup"
        | "audit_page"
        | "backlink_query"
        | "ai_credit"
        | "api_call"
        | "report_render"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      audit_status: [
        "queued",
        "crawling",
        "analyzing",
        "completed",
        "failed",
        "cancelled",
      ],
      check_frequency: ["daily", "weekly", "monthly"],
      issue_severity: ["notice", "warning", "error"],
      job_status: [
        "queued",
        "running",
        "succeeded",
        "failed",
        "cancelled",
        "dead",
      ],
      org_role: ["viewer", "admin", "owner"],
      report_status: ["draft", "queued", "rendering", "ready", "failed"],
      search_device: ["desktop", "mobile"],
      search_engine: ["google", "bing"],
      search_intent: [
        "informational",
        "navigational",
        "commercial",
        "transactional",
      ],
      subscription_status: [
        "trialing",
        "active",
        "past_due",
        "canceled",
        "incomplete",
        "incomplete_expired",
        "unpaid",
        "paused",
      ],
      usage_metric: [
        "serp_query",
        "keyword_lookup",
        "audit_page",
        "backlink_query",
        "ai_credit",
        "api_call",
        "report_render",
      ],
    },
  },
} as const
