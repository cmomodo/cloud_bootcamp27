import { useState } from "react";
import { generateClient } from "aws-amplify/data";
import type { Schema } from "../amplify/data/resource";

const client = generateClient<Schema>();

function ContactForm() {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [inquiryType, setInquiryType] = useState("validation package");
  const [message, setMessage] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submissionResult, setSubmissionResult] = useState<string | null>(null);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setIsSubmitting(true);
    setSubmissionResult(null);

    try {
      const apiEndpoint =
        "https://c88tuouvoe.execute-api.us-east-1.amazonaws.com";

      const formData = {
        name,
        email,
        phone,
        inquiry_type: inquiryType,
        message,
      };

      const response = await fetch(`${apiEndpoint}/submit`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(formData),
      });

      if (!response.ok) {
        throw new Error(`API error: ${response.statusText}`);
      }

      const result = await response.json();
      const submissionData = JSON.parse(result.body || result);
      const referenceId = submissionData.submission_id || "submitted";

      setSubmissionResult(
        `🎉 Thank you for your submission! Your reference number is: ${referenceId}. We'll reply within 24 hours!`
      );
      // Reset form
      setName("");
      setEmail("");
      setPhone("");
      setInquiryType("validation package");
      setMessage("");
    } catch (error) {
      console.error("Error submitting form:", error);
      setSubmissionResult(
        "😔 There was an error submitting your form. Please try again."
      );
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div>
      <h2>Contact Us</h2>
      <form onSubmit={handleSubmit}>
        <div>
          <label htmlFor="name">Name:</label>
          <input
            type="text"
            id="name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            required
          />
        </div>
        <div>
          <label htmlFor="email">Email:</label>
          <input
            type="email"
            id="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
        </div>
        <div>
          <label htmlFor="phone">Phone (optional):</label>
          <input
            type="tel"
            id="phone"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
          />
        </div>
        <div>
          <label htmlFor="inquiryType">Inquiry Type:</label>
          <select
            id="inquiryType"
            value={inquiryType}
            onChange={(e) => setInquiryType(e.target.value)}
            required
          >
            <option value="validation package">Vacation Package</option>
            <option value="pricing">Pricing</option>
            <option value="availability">Availability</option>
          </select>
        </div>
        <div>
          <label htmlFor="message">Message:</label>
          <textarea
            id="message"
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            required
          />
        </div>
        {/* Add your CAPTCHA component here */}
        <button type="submit" disabled={isSubmitting}>
          {isSubmitting ? "Submitting..." : "Submit"}
        </button>
      </form>
      {submissionResult && <p>{submissionResult}</p>}
    </div>
  );
}

export default ContactForm;
