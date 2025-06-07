import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    // Retrieve the file identifier from the request body.
    // For example, this might be: "songs/Do+You+Wanna+Be+Perfect"
    const { fileIdentifier } = await req.json();
    if (!fileIdentifier) {
      throw new Error("File identifier is required");
    }

    // Retrieve Backblaze credentials from environment variables.
    const applicationKeyId = Deno.env.get("B2_APPLICATION_KEY_ID");
    const applicationKey = Deno.env.get("B2_APPLICATION_KEY");
    const bucketName = Deno.env.get("B2_BUCKET_NAME");
    if (!applicationKeyId || !applicationKey || !bucketName) {
      throw new Error("Missing Backblaze credentials");
    }

    // 1. Get authorization token from Backblaze B2.
    const authResponse = await fetch("https://api.backblazeb2.com/b2api/v2/b2_authorize_account", {
      headers: {
        "Authorization": "Basic " + btoa(`${applicationKeyId}:${applicationKey}`),
      },
    });
    if (!authResponse.ok) {
      throw new Error("Failed to authenticate with Backblaze");
    }
    const authData = await authResponse.json();
    const { apiUrl, authorizationToken, accountId, downloadUrl } = authData;

    // 2. Retrieve the bucketId using the given bucketName.
    const bucketsResponse = await fetch(`${apiUrl}/b2api/v2/b2_list_buckets`, {
      method: "POST",
      headers: {
        "Authorization": authorizationToken,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        accountId: accountId,
        bucketName: bucketName,
      }),
    });
    if (!bucketsResponse.ok) {
      throw new Error("Failed to get bucket ID");
    }
    const bucketsData = await bucketsResponse.json();
    if (!bucketsData.buckets || bucketsData.buckets.length === 0) {
      throw new Error("Bucket not found");
    }
    const bucketId = bucketsData.buckets[0].bucketId;

    // 3. Build the final file name.
    // If the fileIdentifier does not end with ".mp3", append it.
    // Do not change the plus signs since they are part of the file name.
    const finalIdentifier = fileIdentifier.endsWith(".mp3")
      ? fileIdentifier
      : fileIdentifier + ".mp3";

    // 4. Request a download authorization using finalIdentifier.
    // The fileNamePrefix passed here must match the file name stored on Backblaze.
    const downloadResponse = await fetch(`${apiUrl}/b2api/v2/b2_get_download_authorization`, {
      method: "POST",
      headers: {
        "Authorization": authorizationToken,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        bucketId: bucketId,
        fileNamePrefix: finalIdentifier,
        validDurationInSeconds: 3600, // URL valid for 1 hour
      }),
    });
    if (!downloadResponse.ok) {
      throw new Error("Failed to get download authorization");
    }
    const downloadData = await downloadResponse.json();
    const downloadToken = downloadData.authorizationToken;

    // 5. Construct the signed URL.
    // We do NOT further manipulate the finalIdentifier so that plus signs remain intact.
    const signedUrl = `${downloadUrl}/file/${bucketName}/${finalIdentifier}?Authorization=${downloadToken}`;

    return new Response(JSON.stringify({ signedUrl }), {
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
      status: 200,
    });
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: error.message,
      }),
      {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
        status: 400,
      }
    );
  }
});