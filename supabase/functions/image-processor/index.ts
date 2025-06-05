/* 
 * Image Optimization Function
 * This Edge Function handles image optimization and transformation to improve performance
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { processImage } from 'https://deno.land/x/deno_image_processor@v0.0.2/mod.ts'

// Create a Supabase client with the Admin key
const supabaseClient = createClient(
  // Supabase API URL - env var exported by default.
  Deno.env.get('SUPABASE_URL') ?? '',
  // Supabase API ANON KEY - env var exported by default
  Deno.env.get('SUPABASE_ANON_KEY') ?? ''
)

// Helper function to parse URL query parameters
function getQueryParam(url: URL, param: string): string | null {
  return url.searchParams.get(param)
}

serve(async (req) => {
  // Start timer for performance tracking
  const startTime = performance.now()
  
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST',
        'Access-Control-Allow-Headers': 'Authorization, Content-Type',
      },
    })
  }

  try {
    const url = new URL(req.url)
    
    // GET request for processing images
    if (req.method === 'GET') {
      // Get image parameters from URL
      const bucket = getQueryParam(url, 'bucket') || 'images'
      const path = getQueryParam(url, 'path')
      const width = parseInt(getQueryParam(url, 'width') || '0', 10)
      const height = parseInt(getQueryParam(url, 'height') || '0', 10)
      const quality = parseInt(getQueryParam(url, 'quality') || '80', 10)
      const format = getQueryParam(url, 'format') || 'webp'
      
      if (!path) {
        return new Response(JSON.stringify({ error: 'Path is required' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        })
      }
      
      // Retrieve the original image from Storage
      const { data: fileData, error: fileError } = await supabaseClient
        .storage
        .from(bucket)
        .download(path)
        
      if (fileError) {
        return new Response(JSON.stringify({ error: 'Image not found' }), {
          status: 404,
          headers: { 'Content-Type': 'application/json' },
        })
      }
      
      // Process the image
      let processedImage = fileData
      
      try {
        // Only process if width or height is specified
        if (width > 0 || height > 0) {
          processedImage = await processImage(fileData, {
            resize: {
              width,
              height,
              fit: 'cover',
            },
            compress: {
              quality,
            },
            format,
          })
        }
        
        // Track processing time
        const endTime = performance.now()
        const processingTime = endTime - startTime
        
        // Log performance (but don't await this)
        supabaseClient.rpc('monitoring.log_api_performance', {
          p_path: '/functions/v1/image-processor',
          p_method: 'GET',
          p_status_code: 200,
          p_response_time_ms: processingTime,
          p_request_payload: { bucket, path, width, height, quality, format },
          p_client_info: { image_processing: true }
        }).then()
        
        // Set appropriate content type
        let contentType: string
        switch (format.toLowerCase()) {
          case 'png':
            contentType = 'image/png'
            break
          case 'jpg':
          case 'jpeg':
            contentType = 'image/jpeg'
            break
          case 'webp':
            contentType = 'image/webp'
            break
          case 'avif':
            contentType = 'image/avif'
            break
          default:
            contentType = 'image/webp'
        }
        
        // Return the processed image
        return new Response(processedImage, {
          headers: {
            'Content-Type': contentType,
            'Cache-Control': 'max-age=31536000, immutable', // Cache for 1 year
          },
        })
      } catch (processingError) {
        console.error('Image processing error:', processingError)
        
        // Fall back to original image if processing fails
        return new Response(fileData, {
          headers: {
            'Content-Type': 'image/*',
            'Cache-Control': 'max-age=3600', // Cache for 1 hour
          },
        })
      }
    }
    
    // POST request for batch optimization
    else if (req.method === 'POST') {
      const { bucket, files, options } = await req.json()
      
      if (!bucket || !files || !Array.isArray(files) || files.length === 0) {
        return new Response(JSON.stringify({ error: 'Invalid request parameters' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        })
      }
      
      const results = []
      const errors = []
      
      // Process each file
      for (const file of files) {
        try {
          // Retrieve the original image
          const { data: fileData, error: fileError } = await supabaseClient
            .storage
            .from(bucket)
            .download(file)
            
          if (fileError) {
            errors.push({ file, error: 'File not found' })
            continue
          }
          
          // Apply optimization settings
          const optimizedImage = await processImage(fileData, {
            resize: options?.resize || { width: 800 },
            compress: options?.compress || { quality: 80 },
            format: options?.format || 'webp',
          })
          
          // Create an optimized filename
          const filenameParts = file.split('.')
          const extension = options?.format || 'webp'
          const optimizedPath = `${filenameParts[0]}_optimized.${extension}`
          
          // Upload the optimized image
          const { data: uploadData, error: uploadError } = await supabaseClient
            .storage
            .from(bucket)
            .upload(optimizedPath, optimizedImage, {
              contentType: `image/${extension}`,
              upsert: true,
            })
            
          if (uploadError) {
            errors.push({ file, error: 'Failed to upload optimized image' })
            continue
          }
          
          // Get the public URL
          const { data: urlData } = supabaseClient
            .storage
            .from(bucket)
            .getPublicUrl(optimizedPath)
            
          results.push({
            originalFile: file,
            optimizedFile: optimizedPath,
            publicUrl: urlData?.publicUrl,
          })
        } catch (err) {
          errors.push({ file, error: err.message || 'Unknown error' })
        }
      }
      
      // Track batch processing time
      const endTime = performance.now()
      const processingTime = endTime - startTime
      
      // Log performance (but don't await this)
      supabaseClient.rpc('monitoring.log_api_performance', {
        p_path: '/functions/v1/image-processor',
        p_method: 'POST',
        p_status_code: 200,
        p_response_time_ms: processingTime,
        p_request_payload: { batchSize: files.length },
        p_client_info: { batch_image_processing: true }
      }).then()
      
      return new Response(
        JSON.stringify({
          results,
          errors,
          processingTimeMs: processingTime,
          success: results.length > 0,
        }),
        {
          headers: { 'Content-Type': 'application/json' },
        }
      )
    }
    
    // Method not allowed
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Image processing error:', error)
    
    return new Response(
      JSON.stringify({
        error: error.message || 'Unknown error',
      }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    )
  }
})
